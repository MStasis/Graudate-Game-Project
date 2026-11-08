param([switch]$HostGame, [string]$JoinAddress = '', [int]$Port = 24570)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExe = Join-Path $projectRoot 'runtime\godot\Godot_v4.7.2-stable_win64.exe'
$gamePath = Join-Path $projectRoot 'game'
$env:APPDATA = Join-Path $projectRoot 'runtime\coop_appdata'
$engineArgs = @('--path', ('"' + $gamePath + '"'), 'res://scenes/CoopProbe.tscn', '--', ('--coop-port=' + $Port))
if ($HostGame) { $engineArgs += '--coop-host' }
elseif ($JoinAddress) { $engineArgs += ('--coop-join=' + $JoinAddress) }
Start-Process -FilePath $godotExe -ArgumentList $engineArgs -WorkingDirectory $projectRoot -WindowStyle Normal | Out-Null
