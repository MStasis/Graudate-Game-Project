param([switch]$Editor, [switch]$Evidence, [ValidateSet('', 'RuleBased', 'LocalLLM', 'Jev')][string]$Provider = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExe = Join-Path $projectRoot 'runtime\godot\Godot_v4.7.2-stable_win64.exe'
$ollamaExe = Join-Path $projectRoot 'runtime\ollama\ollama.exe'
$gamePath = Join-Path $projectRoot 'game'
$settingsText = Get-Content -LiteralPath (Join-Path $gamePath 'resources\NPCSettings.tres') -Raw -Encoding UTF8
$modelName = 'qwen3:4b'
$serverHost = '127.0.0.1'
$serverPort = 11434
if ($settingsText -match '(?m)^model\s*=\s*"([^"]+)"') { $modelName = $Matches[1] }
if ($settingsText -match '(?m)^host\s*=\s*"([^"]+)"') { $serverHost = $Matches[1] }
if ($settingsText -match '(?m)^port\s*=\s*(\d+)') { $serverPort = [int]$Matches[1] }
$serverUrl = 'http://{0}:{1}' -f $serverHost, $serverPort
$evidencePath = Join-Path $projectRoot 'evidence'
if (-not $Provider) {
    $experimentText = Get-Content -LiteralPath (Join-Path $gamePath 'resources\ExperimentSettings.tres') -Raw -Encoding UTF8
    $providerIndex = 0
    if ($experimentText -match '(?m)^provider\s*=\s*(\d+)') { $providerIndex = [int]$Matches[1] }
    $Provider = @('RuleBased', 'LocalLLM', 'Jev')[$providerIndex]
}
if ($Evidence) { $Provider = 'RuleBased' }
New-Item -ItemType Directory -Path $evidencePath -Force | Out-Null
if (-not (Test-Path -LiteralPath $godotExe)) { throw 'Godot runtime is missing. Read README.md.' }
$env:APPDATA = Join-Path $projectRoot 'runtime\appdata'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
try {
    $serverReady = $false
    try {
        $null = Invoke-RestMethod -Uri ($serverUrl + '/api/version') -TimeoutSec 2
        $serverReady = $true
    } catch { }
    if (-not $serverReady) {
        if ($serverHost -notin @('127.0.0.1', 'localhost')) { throw 'The configured remote AI server is unavailable.' }
        if (-not (Test-Path -LiteralPath $ollamaExe)) { throw 'Ollama runtime is missing. Read README.md.' }
        $env:OLLAMA_HOST = '{0}:{1}' -f $serverHost, $serverPort
        $env:OLLAMA_MODELS = Join-Path $projectRoot 'runtime\models'
        $env:OLLAMA_NO_CLOUD = '1'
        $env:OLLAMA_KEEP_ALIVE = '15m'
        Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -WindowStyle Hidden -WorkingDirectory $projectRoot -RedirectStandardOutput (Join-Path $evidencePath 'ollama_stdout.log') -RedirectStandardError (Join-Path $evidencePath 'ollama_stderr.log') | Out-Null
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 500
            try {
                $null = Invoke-RestMethod -Uri ($serverUrl + '/api/version') -TimeoutSec 2
                $serverReady = $true
                break
            } catch { }
        }
    }
    if (-not $serverReady) { throw 'Local Ollama server did not start. Read evidence/ollama_stderr.log.' }
    $modelList = Invoke-RestMethod -Uri ($serverUrl + '/api/tags') -TimeoutSec 5
    if (-not ($modelList.models | Where-Object { $_.name -eq $modelName })) {
        if ($Editor) { Write-Warning ($modelName + ' is not downloaded yet. The editor will still open.') }
        else { throw ($modelName + ' is not downloaded. With the local server running, use runtime\ollama\ollama.exe pull ' + $modelName) }
    }
} catch {
    if ($Editor -or $Provider -ne 'LocalLLM') { Write-Warning ('AI preparation: ' + $_.Exception.Message + ' Rule-based mode and scene editing remain available.') }
    else { throw }
}
$engineArgs = @('--path', ('"' + $gamePath + '"'), '--log-file', ('"' + (Join-Path $evidencePath 'godot_live.log') + '"'))
if ($Editor) { $engineArgs += @('--editor', '--maximized', 'res://scenes/World.tscn') }
if (-not $Editor) { $engineArgs += @('--', ('--provider=' + $Provider)) }
if ($Evidence) { $engineArgs += '--mission-evidence' }
$gameProcess = Start-Process -FilePath $godotExe -ArgumentList $engineArgs -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
Write-Host ('Started Godot. Process ID: ' + $gameProcess.Id)

