param([switch]$Render, [int]$Port = 24571)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$godotExe = Join-Path $projectRoot 'runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
$evidencePath = Join-Path $projectRoot 'evidence\coop_probe'
$env:APPDATA = Join-Path $projectRoot 'runtime\coop_test_appdata'
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
$started = [DateTime]::UtcNow
$ownedProcesses = @()
try {
    foreach ($role in @('host', 'client')) {
        $engineArgs = @('--path', ('"' + $gamePath + '"'), '--script', 'res://tests/coop_probe_test.gd')
        if ($Render) { $engineArgs += @('--resolution', '1280x800', '--audio-driver', 'Dummy') }
        else { $engineArgs += '--headless' }
        $engineArgs += @('--', ('--test-role=' + $role), ('--test-port=' + $Port))
        $process = Start-Process -FilePath $godotExe -ArgumentList $engineArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidencePath ($role + '.log')) -RedirectStandardError (Join-Path $evidencePath ($role + '_stderr.log'))
        $ownedProcesses += $process
        if ($role -eq 'host') { Start-Sleep -Milliseconds 400 }
    }
    foreach ($process in $ownedProcesses) {
        if (-not $process.WaitForExit(40000)) { throw 'Coop verification timed out. See evidence/coop_probe.' }
        if ($process.ExitCode -ne 0) { throw ('Coop process failed with exit ' + $process.ExitCode + '. See evidence/coop_probe.') }
    }
    $total = 0
    foreach ($role in @('host', 'client')) {
        $path = Join-Path $evidencePath ($role + '.json')
        $result = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $result.passed -or -not $result.real_enet_two_processes -or (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $started) { throw ('Fresh ' + $role + ' result failed.') }
        $total += $result.check_count
    }
    & $godotExe --headless --path $gamePath --script res://tests/coop_input_test.gd --log-file (Join-Path $evidencePath 'input.log') -- --mission-test --provider=RuleBased
    if ($LASTEXITCODE -ne 0) { throw 'Coop short-click/input/audio checks failed.' }
    $inputPath = Join-Path $evidencePath 'input.json'
    $inputResult = Get-Content -LiteralPath $inputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $inputResult.passed -or (Get-Item -LiteralPath $inputPath).LastWriteTimeUtc -lt $started) { throw 'Fresh input result failed.' }
    $total += $inputResult.check_count
    Write-Output ('COOP_VERIFIED checks=' + $total + ' real_enet_processes=2 two_pc_lan_tested=false rendered=' + [bool]$Render)
} finally {
    foreach ($process in $ownedProcesses) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
        $process.Dispose()
    }
}
