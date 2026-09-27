# apply.ps1 — 交付卡片「打开」按钮改绑系统默认程序（A 方案）
# 幂等：已打过会跳过；自动备份 *.bak-before-native-open。
$ErrorActionPreference = 'Stop'

$roots = @("$env:LOCALAPPDATA\npm-cache\_npx", "$env:APPDATA\npm\node_modules", "$env:USERPROFILE\.dsh\profiles")
$hits = @()
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  $hits += Get-ChildItem -Path $r -Recurse -Directory -Filter 'dsh-client-ui-deliverables' -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName 'lib\client.js') } | Select-Object -ExpandProperty FullName
}
$hits = $hits | Sort-Object -Unique
if ($hits.Count -eq 0) { throw '找不到 dsh-client-ui-deliverables（请修改脚本顶部的 $roots）' }

$old = @'
onClick: onPreview,
								children: t("presented.action")
'@
$new = @'
onClick: () => onAction("open"),
								children: t("presented.action")
'@
$oldLF = $old.Replace("`r`n", "`n"); $newLF = $new.Replace("`r`n", "`n")

foreach ($dir in $hits) {
  $cur = Join-Path (Join-Path $dir 'lib') 'client.js'
  $src = [System.IO.File]::ReadAllText($cur)
  if ($src.Contains('onAction("open")')) { "$cur : 已打过补丁，跳过"; continue }
  $useOld = $old; $useNew = $new
  if (-not $src.Contains($useOld)) { $useOld = $oldLF; $useNew = $newLF }
  if (-not $src.Contains($useOld)) { "$cur : 锚点未命中，跳过（版本可能不同）"; continue }
  $bak = "$cur.bak-before-native-open"
  if (-not (Test-Path $bak)) { [System.IO.File]::WriteAllText($bak, $src, (New-Object System.Text.UTF8Encoding($false))) }
  [System.IO.File]::WriteAllText($cur, $src.Replace($useOld, $useNew), (New-Object System.Text.UTF8Encoding($false)))
  $chk = [System.IO.File]::ReadAllText($cur)
  "$cur : 已打补丁；onPreview 剩余 $(([regex]::Matches($chk, 'onClick: onPreview')).Count) 处（应为 1）；备份 = $bak"
}
'完成。刷新浏览器页面即可生效。'
