# apply.ps1 — 给 dsh-better-sidebar 打「turn-tail 共存」补丁
# 作用：present 交付轮次让位给 DSH 官方交付卡片，与侧栏「本次产出」行共存。
# 特性：幂等（已打过会跳过）、先备份、按锚点定位（不依赖行号）。
# 用法：pwsh -File apply.ps1   或   powershell -ExecutionPolicy Bypass -File apply.ps1

$ErrorActionPreference = 'Stop'

# 1) 定位插件目录（npm 缓存型 npx 检出 / 全局 / 自定义）
$roots = @(
  "$env:LOCALAPPDATA\npm-cache\_npx",
  "$env:APPDATA\npm\node_modules",
  "$env:USERPROFILE\.dsh\profiles"
)
$hits = @()
foreach ($r in $roots) {
  if (-not (Test-Path $r)) { continue }
  $hits += Get-ChildItem -Path $r -Recurse -Directory -Filter 'dsh-better-sidebar' -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName 'lib\client.js') } |
           Select-Object -ExpandProperty FullName
}
$hits = $hits | Sort-Object -Unique
if ($hits.Count -eq 0) { throw '找不到 dsh-better-sidebar（请修改脚本顶部的 $roots）' }

$old = @'
		function selectProducedFiles(owner) {
			const record = owner;
'@
$new = @'
		function selectProducedFiles(owner) {
			// [local patch · 共存] 本轮若有 present 交付（turn data 的 deliverables.presented
			// 非空），本行不接管，让 @deepseek-ai/dsh-client-ui-deliverables 的交付卡片渲染。
			// 回退：用同目录 *.bak-before-coexist 覆盖。
			{
				const _d = owner?.turn?.data?.get?.("deliverables");
				if (Array.isArray(_d?.presented) && _d.presented.length > 0) return null;
			}
			const record = owner;
'@
$oldLF = $old.Replace("`r`n", "`n"); $newLF = $new.Replace("`r`n", "`n")

foreach ($dir in $hits) {
  foreach ($name in @('client.js', 'client-registry.js')) {
    $cur = Join-Path (Join-Path $dir 'lib') $name
    if (-not (Test-Path $cur)) { continue }
    $src = [System.IO.File]::ReadAllText($cur)
    if ($src.Contains('[local patch')) { "$name : 已打过补丁，跳过"; continue }
    $useOld = $old; $useNew = $new
    if (-not $src.Contains($useOld)) { $useOld = $oldLF; $useNew = $newLF }
    if (-not $src.Contains($useOld)) { "$name : 锚点未命中，跳过（版本可能不同）"; continue }
    $bak = "$cur.bak-before-coexist"
    if (-not (Test-Path $bak)) { [System.IO.File]::WriteAllText($bak, $src, (New-Object System.Text.UTF8Encoding($false))) }
    [System.IO.File]::WriteAllText($cur, $src.Replace($useOld, $useNew), (New-Object System.Text.UTF8Encoding($false)))
    "$name : 已打补丁（$(($src.Length)) -> $((Get-Item $cur).Length) 字节），备份 = $bak"
  }
}
'完成。刷新浏览器页面即可生效。'
