# revert.ps1 — 回退「turn-tail 共存」补丁（用备份覆盖并删除备份）
$ErrorActionPreference = 'Stop'

$roots = @("$env:LOCALAPPDATA\npm-cache\_npx", "$env:APPDATA\npm\node_modules", "$env:USERPROFILE\.dsh\profiles")
$hits = @()
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  $hits += Get-ChildItem -Path $r -Recurse -Directory -Filter 'dsh-better-sidebar' -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName 'lib\client.js') } | Select-Object -ExpandProperty FullName
}
$hits = $hits | Sort-Object -Unique
if ($hits.Count -eq 0) { throw '找不到 dsh-better-sidebar' }

foreach ($dir in $hits) {
  foreach ($name in @('client.js', 'client-registry.js')) {
    $cur = Join-Path (Join-Path $dir 'lib') $name
    $bak = "$cur.bak-before-coexist"
    if (-not (Test-Path $bak)) { "$name : 无备份，跳过"; continue }
    Copy-Item $bak $cur -Force
    $same = (Get-FileHash $cur -Algorithm SHA256).Hash -eq (Get-FileHash $bak -Algorithm SHA256).Hash
    Remove-Item $bak -Force
    "$name : 已回退（哈希一致 = $same）"
  }
}
'完成。刷新浏览器页面即可生效。'
