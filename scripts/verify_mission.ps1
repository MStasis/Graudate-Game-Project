param([switch]$Render, [switch]$LocalAI)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExe = Join-Path $projectRoot 'runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
$gamePath = Join-Path $projectRoot 'game'
$evidencePath = Join-Path $projectRoot 'evidence'
$env:APPDATA = Join-Path $projectRoot 'runtime\appdata'
$started = [DateTime]::UtcNow
New-Item -ItemType Directory -Force -Path $evidencePath | Out-Null
& $godotExe --headless --editor --path $gamePath --import --quit *> (Join-Path $evidencePath 'verification_import.log')
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath (Join-Path $evidencePath 'verification_import.log') -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) { throw 'Project import/compile failed. Check verification_import.log.' }
function Invoke-HiddenGodot([string[]]$EngineArguments, [string]$Stem) {
    $quotedArguments = @($EngineArguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $process = Start-Process -FilePath $godotExe -ArgumentList $quotedArguments -WindowStyle Hidden -WorkingDirectory $projectRoot -Wait -PassThru -RedirectStandardOutput (Join-Path $evidencePath ($Stem + '_stdout.log')) -RedirectStandardError (Join-Path $evidencePath ($Stem + '_stderr.log'))
    if ($process.ExitCode -ne 0) { throw ($Stem + ' failed. Check the fresh stdout/stderr logs.') }
}
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
& $godotExe --headless --path $gamePath --script res://tests/noncombat_dialogue_test.gd --log-file (Join-Path $evidencePath 'noncombat_ui\noncombat_dialogue_test.log') -- --noncombat-ui-test --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Noncombat dialogue UI tests failed.' }
$noncombatPath = Join-Path $evidencePath 'noncombat_ui\noncombat_dialogue_test.json'
$noncombatResult = Get-Content -LiteralPath $noncombatPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $noncombatResult.passed -or (Get-Item -LiteralPath $noncombatPath).LastWriteTimeUtc -lt $started) { throw 'Fresh noncombat UI result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/interface_update_test.gd --log-file (Join-Path $evidencePath 'interface_update\interface_update_test.log') -- --interface-test --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Interface update regression tests failed.' }
$interfacePath = Join-Path $evidencePath 'interface_update\interface_update_test.json'
$interfaceResult = Get-Content -LiteralPath $interfacePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $interfaceResult.passed -or (Get-Item -LiteralPath $interfacePath).LastWriteTimeUtc -lt $started) { throw 'Fresh interface update result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/mission_mechanics_test.gd --log-file (Join-Path $evidencePath 'mechanics.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Mission mechanism regression tests failed.' }
$mechanicsPath = Join-Path $evidencePath 'mission_mechanics\test.json'
$mechanicsResult = Get-Content -LiteralPath $mechanicsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $mechanicsResult.passed -or (Get-Item -LiteralPath $mechanicsPath).LastWriteTimeUtc -lt $started) { throw 'Fresh mechanism result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/input_aim_collision_test.gd --log-file (Join-Path $evidencePath 'input_aim_collision.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Chat, mouse flashlight, or prop collision tests failed.' }
$inputCollisionPath = Join-Path $evidencePath 'input_aim_collision\test.json'
$inputCollisionResult = Get-Content -LiteralPath $inputCollisionPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $inputCollisionResult.passed -or (Get-Item -LiteralPath $inputCollisionPath).LastWriteTimeUtc -lt $started) { throw 'Fresh input/collision result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/dialogue_notice_test.gd --log-file (Join-Path $evidencePath 'dialogue_notices.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Dialogue/system notification regression failed.' }
$dialogueNoticePath = Join-Path $evidencePath 'dialogue_notices\test.json'
$dialogueNoticeResult = Get-Content -LiteralPath $dialogueNoticePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $dialogueNoticeResult.passed -or (Get-Item -LiteralPath $dialogueNoticePath).LastWriteTimeUtc -lt $started) { throw 'Fresh dialogue/notification result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/harin_upgrade_test.gd --log-file (Join-Path $evidencePath 'harin_upgrade.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Harin companion regression failed.' }
$harinPath = Join-Path $evidencePath 'harin_upgrade\test.json'
$harinResult = Get-Content -LiteralPath $harinPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $harinResult.passed -or (Get-Item -LiteralPath $harinPath).LastWriteTimeUtc -lt $started) { throw 'Fresh companion result was not verified.' }
& $godotExe --headless --path $gamePath --script res://tests/story_ui_test.gd --log-file (Join-Path $evidencePath 'story_ui.log') -- --mission-test --provider=RuleBased
if ($LASTEXITCODE -ne 0) { throw 'Story, map, journal and status regression failed.' }
$storyPath = Join-Path $evidencePath 'story_ui\test.json'
$storyResult = Get-Content -LiteralPath $storyPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $storyResult.passed -or (Get-Item -LiteralPath $storyPath).LastWriteTimeUtc -lt $started) { throw 'Fresh story/UI result was not verified.' }
if ($Render) {
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/story_ui_test.gd', '--', '--mission-test', '--provider=RuleBased', '--render-story-ui') 'story_ui_render'
    $storyRenderPath = Join-Path $evidencePath 'story_ui\render.json'
    $storyRenderResult = Get-Content -LiteralPath $storyRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $storyRenderResult.passed -or -not $storyRenderResult.gpu_rendered -or (Get-Item -LiteralPath $storyRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered story/UI result was not verified.' }
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/harin_upgrade_test.gd', '--log-file', (Join-Path $evidencePath 'harin_render.log'), '--', '--mission-test', '--provider=RuleBased', '--render-harin') 'harin_render'
    $harinRenderPath = Join-Path $evidencePath 'harin_upgrade\render.json'
    $harinRenderResult = Get-Content -LiteralPath $harinRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $harinRenderResult.passed -or -not $harinRenderResult.gpu_rendered -or (Get-Item -LiteralPath $harinRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered companion result failed.' }
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--log-file', (Join-Path $evidencePath 'mission_render.log'), '--', '--mission-evidence', '--provider=RuleBased') 'mission_render'
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/interface_update_test.gd', '--log-file', (Join-Path $evidencePath 'interface_update\interface_update_render_test.log'), '--', '--interface-test', '--mission-test', '--provider=RuleBased', '--render-interface') 'interface_render'
    $interfaceRenderPath = Join-Path $evidencePath 'interface_update\interface_update_render_test.json'
    $interfaceRenderResult = Get-Content -LiteralPath $interfaceRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $interfaceRenderResult.passed -or -not $interfaceRenderResult.gpu_rendered -or (Get-Item -LiteralPath $interfaceRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered interface result was not verified.' }
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/mission_mechanics_test.gd', '--log-file', (Join-Path $evidencePath 'mechanics_render.log'), '--', '--mission-test', '--provider=RuleBased', '--render-mechanics') 'mechanics_render'
    $mechanicsRenderPath = Join-Path $evidencePath 'mission_mechanics\render.json'
    $mechanicsRenderResult = Get-Content -LiteralPath $mechanicsRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $mechanicsRenderResult.passed -or -not $mechanicsRenderResult.gpu_rendered -or (Get-Item -LiteralPath $mechanicsRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered mechanism result failed.' }
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/input_aim_collision_test.gd', '--log-file', (Join-Path $evidencePath 'input_collision_render.log'), '--', '--mission-test', '--provider=RuleBased', '--render-input-collision') 'input_collision_render'
    $inputCollisionRenderPath = Join-Path $evidencePath 'input_aim_collision\render.json'
    $inputCollisionRenderResult = Get-Content -LiteralPath $inputCollisionRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $inputCollisionRenderResult.passed -or -not $inputCollisionRenderResult.gpu_rendered -or (Get-Item -LiteralPath $inputCollisionRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered input/collision result failed.' }
    Invoke-HiddenGodot @('--path', $gamePath, '--resolution', '1280x800', '--audio-driver', 'Dummy', '--script', 'res://tests/dialogue_notice_test.gd', '--log-file', (Join-Path $evidencePath 'dialogue_notices_render.log'), '--', '--mission-test', '--provider=RuleBased', '--render-dialogue-notices') 'dialogue_notices_render'
    $dialogueNoticeRenderPath = Join-Path $evidencePath 'dialogue_notices\render.json'
    $dialogueNoticeRenderResult = Get-Content -LiteralPath $dialogueNoticeRenderPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $dialogueNoticeRenderResult.passed -or -not $dialogueNoticeRenderResult.gpu_rendered -or (Get-Item -LiteralPath $dialogueNoticeRenderPath).LastWriteTimeUtc -lt $started) { throw 'Fresh rendered dialogue/notification result failed.' }
}
if ($LocalAI) {
    & $godotExe --headless --path $gamePath --script res://tests/story_dialogue_live_test.gd --log-file (Join-Path $evidencePath 'story_dialogue_live.log') -- --mission-test --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live story dialogue transport/provenance regression failed. Semantic review is separate.' }
    & $godotExe --headless --path $gamePath --script res://tests/harin_live_test.gd --log-file (Join-Path $evidencePath 'harin_live.log') -- --mission-test --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live companion dialogue/action regression failed.' }
    & $godotExe --headless --path $gamePath --script res://tests/local_integration.gd --log-file (Join-Path $evidencePath 'local_integration.log') -- --local-integration --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live local AI integration failed. Check the Ollama server.' }
    & $godotExe --headless --path $gamePath --script res://tests/live_save_load_test.gd --log-file (Join-Path $evidencePath 'interface_update\live_save_load.log') -- --interface-test --mission-test --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live save/load request cancellation failed.' }
    & $godotExe --headless --path $gamePath --script res://tests/mechanics_local_ai_test.gd --log-file (Join-Path $evidencePath 'mechanics_local_ai.log') -- --mission-test --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live local model mechanism checks failed.' }
    & $godotExe --headless --path $gamePath --script res://tests/dialogue_quality_test.gd --log-file (Join-Path $evidencePath 'dialogue_live.log') -- --mission-test --provider=LocalLLM
    if ($LASTEXITCODE -ne 0) { throw 'Live local model conversation checks failed.' }
}
Write-Output ('MISSION_VERIFIED gameplay=' + $result.check_count + ' chat=' + $chatResult.check_count + ' native_load=6 native_chat=11 ui=' + $uiResult.check_count + ' noncombat=' + $noncombatResult.check_count + ' interface=' + $interfaceResult.check_count + ' mechanics=' + $mechanicsResult.check_count + ' input_collision=' + $inputCollisionResult.check_count + ' dialogue_notices=' + $dialogueNoticeResult.check_count + ' harin=' + $harinResult.check_count + ' story_ui=' + $storyResult.check_count)
