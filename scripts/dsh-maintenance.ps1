# DSH maintenance script (all strings ASCII on purpose: PowerShell 5.1 reads a
# .ps1 without BOM as ANSI/GBK and mangles non-ASCII text).
#
# Usage:
#   .\dsh-maintenance.ps1                 -> check GitHub progress (default)
#   .\dsh-maintenance.ps1 -Check          -> same
#   .\dsh-maintenance.ps1 -Reapply        -> re-apply the client-bundle patches
#   .\dsh-maintenance.ps1 -Revert         -> revert the patches from their backups
#   .\dsh-maintenance.ps1 -All            -> Reapply + Check
#
# Where the two patches live (they are NOT in the same tree):
#   * dsh-better-sidebar        -> installed INTO the profile: %USERPROFILE%\.dsh\profiles\*\node_modules
#   * dsh-client-ui-deliverables-> part of DSH itself: the npx checkout the live host serves
# The script asks the running host which checkout that is (GET / -> window.__DSH_BOOT__,
# entry URL /plugins/??<pkg>/client.js); other npx cache copies are never touched.

param(
  [switch]$Check,
  [switch]$Reapply,
  [switch]$Revert,
  [switch]$All,
  [string]$Root,                 # override the live checkout path
  [string]$ProfilesRoot = "$env:USERPROFILE\.dsh\profiles"
)

$ErrorActionPreference = 'Continue'
if (-not ($Check -or $Reapply -or $Revert -or $All)) { $Check = $true }
if ($All) { $Reapply = $true; $Check = $true }

# --------------------------------------------------------------- host discovery
function Get-HostToken {
  # the boot payload needs the page token; the launcher writes it into its log
  foreach ($log in @('D:\workspace\dsh-web\coldstart-host.out.log', 'D:\workspace\dsh-web\host.log')) {
    if (-not (Test-Path $log)) { continue }
    $tail = Get-Content $log -Tail 200 -ErrorAction SilentlyContinue
    for ($i = $tail.Count - 1; $i -ge 0; $i--) {
      $m = [regex]::Match($tail[$i], '\?token=([A-Za-z0-9_\-]+)')
      if ($m.Success) { return $m.Groups[1].Value }
    }
  }
  return $null
}

function Get-LiveCheckout {
  $token = Get-HostToken

  # 1) most direct: the running node process argv contains ...\_npx\<hash>\...
  $procs = Get-Process -Name node, nodejs -ErrorAction SilentlyContinue
  foreach ($pr in ($procs | Sort-Object StartTime -Descending)) {
    try {
      $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($pr.Id)" -ErrorAction Stop).CommandLine
    } catch { $cl = $null }
    if (-not $cl) { continue }
    $m = [regex]::Match($cl, '([A-Za-z]:\\[^"'']*?_npx\\[0-9a-f]{8,})')
    if ($m.Success -and (Test-Path $m.Groups[1].Value)) { return $m.Groups[1].Value }
  }

  # 2) boot payload (entries are bare ids, kept as a weak hint only)
  $urls = @()
  foreach ($port in 3080, 3081, 3082) {
    if ($token) { $urls += "http://127.0.0.1:$port/?token=$token" }
    $urls += "http://127.0.0.1:$port/"
  }
  foreach ($u in $urls) {
    try {
      $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
      $idx = $r.Content.IndexOf('__DSH_BOOT__')
      if ($idx -lt 0) { continue }
      $boot = $r.Content.Substring($idx)
      $ms = [regex]::Matches($boot, '/plugins/\?\?([^"&,]+)/client\.js')
      foreach ($m in $ms) {
        $pkg = $m.Groups[1].Value
        if (-not (Test-Path $pkg)) { continue }
        $marker = [char]92 + 'node_modules' + [char]92
        $cut = $pkg.IndexOf($marker)
        if ($cut -gt 0) { return $pkg.Substring(0, $cut) }
      }
    } catch { }
  }

  # 3) last resort: newest checkout that carries the packages we patch
  $npxRoot = "$env:LOCALAPPDATA\npm-cache\_npx"
  if (Test-Path $npxRoot) {
    $c = Get-ChildItem $npxRoot -Directory -ErrorAction SilentlyContinue |
         Where-Object { Test-Path (Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh-client-ui-deliverables\lib\client.js') } |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($c) { return $c.FullName }
  }
  return $null
}

function Get-ProfilePluginDirs {
  $out = @()
  if (Test-Path $ProfilesRoot) {
    $out += Get-ChildItem $ProfilesRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'node_modules' } |
            Where-Object { Test-Path $_ }
  }
  return $out
}

# ---------------------------------------------------------------- patch helpers
function Invoke-Reapply {
  Write-Output '=== Re-apply patches ==='
  $live = if ($Root) { $Root } else { Get-LiveCheckout }
  if (-not $live) { Write-Output '  [warn] live checkout not detected; pass -Root <npx checkout path>' }

  # ---- patch 1: dsh-better-sidebar (lives in the profile node_modules) ----
  $sidebarDirs = @()
  foreach ($nm in Get-ProfilePluginDirs) {
    $d = Join-Path $nm 'dsh-better-sidebar\lib'
    if (Test-Path $d) { $sidebarDirs += $d }
  }
  if ($live) {
    $d = Join-Path $live 'node_modules\dsh-better-sidebar\lib'
    if (Test-Path $d) { $sidebarDirs += $d }
  }
  $sidebarDirs = $sidebarDirs | Sort-Object -Unique

  if ($sidebarDirs.Count -eq 0) { Write-Output '  [skip] dsh-better-sidebar not found' }
  foreach ($dir in $sidebarDirs) {
    $old = '		function selectProducedFiles(owner) {' + "`r`n" + '			const record = owner;'
    $new = @'
		function selectProducedFiles(owner) {
			// [local patch coexist] yield when this turn declared present deliveries
			{
				const _d = owner?.turn?.data?.get?.("deliverables");
				if (Array.isArray(_d?.presented) && _d.presented.length > 0) return null;
			}
			const record = owner;
'@
    foreach ($file in @('client.js', 'client-registry.js')) {
      $cur = Join-Path $dir $file
      if (-not (Test-Path $cur)) { continue }
      $src = [System.IO.File]::ReadAllText($cur)
      if ($src -match 'local patch') { Write-Output "  [skip] sidebar/$file already patched"; continue }
      $u = $old; $v = $new
      if (-not $src.Contains($u)) { $u = $u.Replace("`r`n", "`n"); $v = $v.Replace("`r`n", "`n") }
      if (-not $src.Contains($u)) { Write-Output "  [skip] sidebar/$file anchor not found"; continue }
      $bak = "$cur.bak-before-coexist"
      if (-not (Test-Path $bak)) { [System.IO.File]::WriteAllText($bak, $src, (New-Object System.Text.UTF8Encoding($false))) }
      [System.IO.File]::WriteAllText($cur, $src.Replace($u, $v), (New-Object System.Text.UTF8Encoding($false)))
      Write-Output "  [ok]   sidebar/$file patched  ($dir)"
    }
  }

  # ---- patch 2: dsh-client-ui-deliverables (part of DSH itself) ----
  if ($live) {
    $dir2 = Join-Path $live 'node_modules\@deepseek-ai\dsh-client-ui-deliverables\lib'
    if (-not (Test-Path $dir2)) { Write-Output '  [skip] deliverables not in the live checkout' }
    else {
      $cur = Join-Path $dir2 'client.js'
      $src = [System.IO.File]::ReadAllText($cur)
      if ($src.Contains('onAction("open")')) { Write-Output '  [skip] deliverables already patched' }
      else {
        $u = 'onClick: onPreview,' + "`r`n" + '								children: t("presented.action")'
        $v = 'onClick: () => onAction("open"),' + "`r`n" + '								children: t("presented.action")'
        if (-not $src.Contains($u)) { $u = $u.Replace("`r`n", "`n"); $v = $v.Replace("`r`n", "`n") }
        if (-not $src.Contains($u)) { Write-Output '  [skip] deliverables anchor not found' }
        else {
          $bak = "$cur.bak-before-native-open"
          if (-not (Test-Path $bak)) { [System.IO.File]::WriteAllText($bak, $src, (New-Object System.Text.UTF8Encoding($false))) }
          [System.IO.File]::WriteAllText($cur, $src.Replace($u, $v), (New-Object System.Text.UTF8Encoding($false)))
          Write-Output "  [ok]   deliverables/client.js patched  ($dir2)"
        }
      }
    }
  }
  Write-Output '  (refresh the browser page to take effect)'
}

function Invoke-Revert {
  Write-Output '=== Revert patches ==='
  $live = if ($Root) { $Root } else { Get-LiveCheckout }

  $sidebarDirs = @()
  foreach ($nm in Get-ProfilePluginDirs) {
    $d = Join-Path $nm 'dsh-better-sidebar\lib'
    if (Test-Path $d) { $sidebarDirs += $d }
  }
  if ($live) { $d = Join-Path $live 'node_modules\dsh-better-sidebar\lib'; if (Test-Path $d) { $sidebarDirs += $d } }
  foreach ($dir in ($sidebarDirs | Sort-Object -Unique)) {
    foreach ($file in @('client.js', 'client-registry.js')) {
      $cur = Join-Path $dir $file; $bak = "$cur.bak-before-coexist"
      if (-not (Test-Path $bak)) { Write-Output "  [skip] sidebar/$file no backup"; continue }
      Copy-Item $bak $cur -Force
      $same = (Get-FileHash $cur -Algorithm SHA256).Hash -eq (Get-FileHash $bak -Algorithm SHA256).Hash
      Remove-Item $bak -Force
      Write-Output "  [ok]   sidebar/$file reverted (hash match: $same)"
    }
  }
  if ($live) {
    $cur = Join-Path $live 'node_modules\@deepseek-ai\dsh-client-ui-deliverables\lib\client.js'
    $bak = "$cur.bak-before-native-open"
    if (Test-Path $bak) {
      Copy-Item $bak $cur -Force
      $same = (Get-FileHash $cur -Algorithm SHA256).Hash -eq (Get-FileHash $bak -Algorithm SHA256).Hash
      Remove-Item $bak -Force
      Write-Output "  [ok]   deliverables/client.js reverted (hash match: $same)"
    } else { Write-Output '  [skip] deliverables no backup' }
  }
  Write-Output '  (refresh the browser page to take effect)'
}

# ------------------------------------------------------------- github progress
function Invoke-Check {
  Write-Output '=== GitHub progress check ==='
  Write-Output ("time: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))

  Write-Output ''
  Write-Output '[1] sidebar PR #634 (turn-tail yield)'
  $p = & gh api 'repos/omdsh-dev/DSH-better-sidebar/pulls/634' 2>&1 | Out-String
  try {
    $o = $p | ConvertFrom-Json
    Write-Output ("    state=$($o.state) merged=$($o.merged) draft=$($o.draft) mergeable=$($o.mergeable)/$($o.mergeable_state)")
    Write-Output ("    commits=$($o.commits) comments=$($o.comments) review_comments=$($o.review_comments) updated=$($o.updated_at)")
  } catch { Write-Output '    read failed' }

  $c = & gh api 'repos/omdsh-dev/DSH-better-sidebar/issues/634/comments' 2>&1 | Out-String
  try {
    $cs = @($c | ConvertFrom-Json)
    Write-Output ("    issue comments: " + $cs.Count)
    foreach ($x in $cs) {
      $tag = if ($x.user.login -eq 'bolide737') { ' (me)' } else { '' }
      $body = ($x.body -replace "`r?`n", ' ')
      Write-Output ("      - $($x.user.login)$tag @ $($x.created_at): " + $body.Substring(0, [Math]::Min(80, $body.Length)))
    }
  } catch { }

  Write-Output ''
  Write-Output '[2] DSH discussion #8059 (configurable Open button)'
  $tmp = Join-Path $env:TEMP '_chk_gql.json'
  $q = '{"query": "query { repository(owner: \"deepseek-ai\", name: \"deepseek-harness\") { d: discussion(number: 8059) { title url comments(first: 50) { totalCount nodes { author { login } createdAt bodyText } } } } }"}'
  [System.IO.File]::WriteAllText($tmp, $q, (New-Object System.Text.UTF8Encoding($false)))
  $r = & gh api graphql --input $tmp 2>&1 | Out-String
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  try {
    $d = ($r | ConvertFrom-Json).data.repository.d
    Write-Output ("    $($d.title)")
    Write-Output ("    $($d.url)")
    Write-Output ("    comments: $($d.comments.totalCount)")
    foreach ($x in $d.comments.nodes) {
      $b = ($x.bodyText -replace "`r?`n", ' ')
      Write-Output ("      - $($x.author.login) @ $($x.createdAt): " + $b.Substring(0, [Math]::Min(80, $b.Length)))
    }
  } catch { Write-Output '    read failed' }

  Write-Output ''
  Write-Output '[3] discussion #7549 (cross-reference replies)'
  $q = '{"query": "query { repository(owner: \"deepseek-ai\", name: \"deepseek-harness\") { d: discussion(number: 7549) { title comments(first: 50) { totalCount nodes { author { login } createdAt } } } } }"}'
  [System.IO.File]::WriteAllText($tmp, $q, (New-Object System.Text.UTF8Encoding($false)))
  $r = & gh api graphql --input $tmp 2>&1 | Out-String
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  try {
    $d = ($r | ConvertFrom-Json).data.repository.d
    Write-Output ("    $($d.title)")
    Write-Output ("    comments: $($d.comments.totalCount)")
    foreach ($x in $d.comments.nodes) { Write-Output ("      - $($x.author.login) @ $($x.createdAt)") }
  } catch { Write-Output '    read failed' }

  Write-Output ''
  Write-Output '[4] unread GitHub notifications'
  $n = & gh api 'notifications?all=false&per_page=20' 2>&1 | Out-String
  try {
    $ns = @($n | ConvertFrom-Json | Where-Object { $_.subject -ne $null })
    if ($ns.Count -eq 0) { Write-Output '    none' }
    else { foreach ($x in $ns) { Write-Output ("    - [$($x.reason)] $($x.subject.title)  ($($x.repository.full_name))") } }
  } catch { Write-Output '    read failed' }

  Write-Output ''
  Write-Output '[5] patch repo stats'
  $rp = & gh api 'repos/bolide737/dsh-patches' 2>&1 | Out-String
  try { $o = $rp | ConvertFrom-Json; Write-Output ("    bolide737/dsh-patches stars=$($o.stargazers_count) forks=$($o.forks_count) watchers=$($o.subscribers_count)") } catch { }
  Write-Output '=== done ==='
}

if ($Check)   { Invoke-Check }
if ($Reapply) { Invoke-Reapply }
if ($Revert)  { Invoke-Revert }
