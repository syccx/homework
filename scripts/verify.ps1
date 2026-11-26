param([string]$DevEcoHome = 'D:\DevEco Studio', [switch]$TestsOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
if(-not (Test-Path -LiteralPath $node)) { throw "找不到 DevEco 内置 Node：$node" }
Push-Location -LiteralPath $projectRoot
try {
  foreach($script in @('test-store.cjs','test-forms.cjs','test-pages.cjs','test-date.cjs','test-reactivity.cjs','test-network.cjs')) {
    & $node (Join-Path $PSScriptRoot $script)
    if($LASTEXITCODE -ne 0) { throw "$script 检查未通过" }
  }
  if(-not $TestsOnly) {
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
    $env:NODE_HOME = Join-Path $DevEcoHome 'tools\node'
    & $node (Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js') --mode module -p module=entry@default -p product=default assembleHap --no-daemon
    if($LASTEXITCODE -ne 0) { throw 'HarmonyOS 构建未通过' }
  }
  Write-Output '所有本地检查通过。安装、设备存储与卡片宿主仍需设备验收。'
} finally {
  Pop-Location
}
