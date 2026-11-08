# 원본 효과음: 880Hz, 75ms, 짧은 fade를 가진 프로젝트 자체 제작 단음.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$audioDirectory = Join-Path $projectRoot 'game\assets\audio'
New-Item -ItemType Directory -Path $audioDirectory -Force | Out-Null
$sampleRate = 22050
$sampleCount = [int]($sampleRate * 0.075)
$writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $audioDirectory 'panel_beep.wav')))
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $sampleCount * 2))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([int]16); $writer.Write([int16]1); $writer.Write([int16]1)
    $writer.Write([int]$sampleRate); $writer.Write([int]($sampleRate * 2))
    $writer.Write([int16]2); $writer.Write([int16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([int]($sampleCount * 2))
    for ($sample = 0; $sample -lt $sampleCount; $sample++) {
        $envelope = [Math]::Min(1.0, [Math]::Min($sample / ($sampleRate * 0.005), ($sampleCount - 1 - $sample) / ($sampleRate * 0.008)))
        $writer.Write([int16](32767 * 0.35 * $envelope * [Math]::Sin(2 * [Math]::PI * 880 * $sample / $sampleRate)))
    }
} finally { $writer.Dispose() }
