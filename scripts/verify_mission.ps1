param([switch]$Render, [switch]$LocalAI)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExe = Join-Path $projectRoot 'runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
$gamePath = Join-Path $projectRoot 'game'
$evidencePath = Join-Path $projectRoot 'evidence'
$env:APPDATA = Join-Path $projectRoot 'runtime\appdata'
$started = [DateTime]::UtcNow
& $godotExe --headless --path $gamePath --script res://tests/mission_test.gd --log-file (Join-Path $evidencePath 'mission_test.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Mission tests failed.' }
$resultPath = Join-Path $evidencePath 'mission_v1\mission_test.json'
$result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $result.passed -or $result.check_count -lt 50 -or (Get-Item -LiteralPath $resultPath).LastWriteTimeUtc -lt $started) { throw 'Fresh test result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/chat_input_test.gd --log-file (Join-Path $evidencePath 'chat_input_test.log') -- --chat-input-test --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Chat input regression tests failed.' }
$chatPath = Join-Path $evidencePath 'chat_input_fix\chat_input_test.json'
$chatResult = Get-Content -LiteralPath $chatPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $chatResult.passed -or (Get-Item -LiteralPath $chatPath).LastWriteTimeUtc -lt $started) { throw 'Fresh chat input result was not verified.' }
foreach ($suite in @('native_ime_load_test','native_ime_chat_test')) {
    & $godotExe --headless --path $gamePath --script ('res://tests/' + $suite + '.gd') --log-file (Join-Path $evidencePath ($suite + '.log')) -- --mission-test --provider=RuleBased
    if ($LASTEXITCODE -ne 0) { throw ($suite + ' failed.') }
}
$nativeLoadPath = Join-Path $evidencePath 'native_ime_fix\native_load_test.json'
$nativeChatPath = Join-Path $evidencePath 'native_ime_fix\chat_native_integration_test.json'
foreach ($path in @($nativeLoadPath, $nativeChatPath)) {
    $nativeResult = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $nativeResult.passed -or (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $started) { throw 'Fresh native IME result was not verified.' }
}
& $godotExe --headless --path $gamePath --script res://tests/ui_layout_test.gd --log-file (Join-Path $evidencePath 'ui_redesign\ui_layout_test.log') -- --ui-layout-test --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'UI regression tests failed.' }
$uiPath = Join-Path $evidencePath 'ui_redesign\ui_layout_test.json'
$uiResult = Get-Content -LiteralPath $uiPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $uiResult.passed -or (Get-Item -LiteralPath $uiPath).LastWriteTimeUtc -lt $started) { throw 'Fresh UI result was not verified.' }
if ($Render) {
    & $godotExe --path $gamePath --resolution 1280x800 --log-file (Join-Path $evidencePath 'mission_render.log') -- --mission-evidence --provider=RuleBased
    if ($LASTEXITCODE -ne 0) { throw 'Rendered mission flow failed.' }
}
if ($LocalAI) {
    & $godotExe --headless --path $gamePath --script res://tests/local_integration.gd --log-file (Join-Path $evidencePath 'local_integration.log') -- --local-integration --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live local AI integration failed. Check the Ollama server.' }
}
Write-Output ('MISSION_VERIFIED gameplay=' + $result.check_count + ' chat=' + $chatResult.check_count + ' native_load=6 native_chat=11 ui=' + $uiResult.check_count)
