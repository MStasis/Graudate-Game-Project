param(
    [Parameter(Mandatory = $true)][string]$TemplatesArchive,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot 'runtime/godot'
$version = '4.7.2-stable'
$engineName = "Godot_v${version}_win64"
$archive = (Resolve-Path -LiteralPath $TemplatesArchive).Path
$expectedHash = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Use the official Godot 4.7.2 standard export templates archive.'
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'build' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zipPath = Join-Path $output 'ContainmentDemo-Windows-x64.zip'
if (Test-Path -LiteralPath $zipPath) { throw "The output already exists: $zipPath. Choose another -OutputDirectory." }

$runName = 'windows_package_' + [Guid]::NewGuid().ToString('N')
$runRoot = Join-Path $projectRoot ('runtime/' + $runName)
$gameCopy = Join-Path $runRoot 'game'
$engineCopy = Join-Path $runRoot 'godot'
$templateDir = Join-Path $engineCopy 'editor_data/export_templates/4.7.2.stable'
$bundle = Join-Path $runRoot 'ContainmentDemo'
$licenses = Join-Path $bundle 'licenses'
New-Item -ItemType Directory -Path $gameCopy,$templateDir,$licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $engine "$engineName.exe"),(Join-Path $engine "${engineName}_console.exe") -Destination $engineCopy
New-Item -ItemType File -Path (Join-Path $engineCopy '_sc_') | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$templates = [IO.Compression.ZipFile]::OpenRead($archive)
try {
    $release = $templates.GetEntry('templates/windows_release_x86_64.exe')
    if (-not $release) { throw 'The archive is missing the Windows x64 release template.' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($release, (Join-Path $templateDir 'windows_release_x86_64.exe'))
} finally {
    $templates.Dispose()
}

robocopy (Join-Path $projectRoot 'game') $gameCopy /E /XD .godot /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "Copy failed: $LASTEXITCODE" }
$godot = Join-Path $engineCopy "${engineName}_console.exe"
$importLog = Join-Path $runRoot 'import.log'
$exportLog = Join-Path $runRoot 'export.log'
$previousAppData = $env:APPDATA
$env:APPDATA = Join-Path $runRoot 'appdata'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
try {
    & $godot --headless --editor --path $gameCopy --import --quit *> $importLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) {
        throw "Import failed. See $importLog."
    }
    & $godot --headless --path $gameCopy --export-release 'Windows x64' (Join-Path $bundle 'ContainmentDemo.exe') *> $exportLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern '(^ERROR:|SCRIPT ERROR)' -Quiet)) {
        throw "Export failed. See $exportLog."
    }
} finally {
    $env:APPDATA = $previousAppData
}
foreach ($name in @('ContainmentDemo.exe','ContainmentDemo.pck','windows_ime.dll')) {
    if (-not (Get-ChildItem -LiteralPath $bundle -Recurse -File -Filter $name)) {
        throw "Export is missing $name. See $exportLog."
    }
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'distribution/PLAY-KO.txt') -Destination $bundle
Copy-Item -Path (Join-Path $projectRoot 'distribution/licenses/*') -Destination $licenses
Copy-Item -Path (Join-Path $projectRoot 'game/assets/temporary/kenney/licenses/*') -Destination $licenses
Copy-Item -LiteralPath (Join-Path $projectRoot 'game/assets/ui/ASSET_SOURCE.md'),(Join-Path $projectRoot 'game/assets/ui/HARIN_BUST_SOURCE.md') -Destination $licenses
Copy-Item -LiteralPath (Join-Path $projectRoot 'game/assets/fleet_sprites/README.md') -Destination (Join-Path $licenses 'FLEET_SPRITES_SOURCE.md')
$temporaryZip = Join-Path $runRoot 'ContainmentDemo-Windows-x64.zip'
Compress-Archive -LiteralPath $bundle -DestinationPath $temporaryZip -CompressionLevel Optimal
Copy-Item -LiteralPath $temporaryZip -Destination $zipPath
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  ContainmentDemo-Windows-x64.zip" | Set-Content -LiteralPath ($zipPath + '.sha256') -Encoding ascii
Write-Output "Package: $zipPath"
Write-Output "SHA-256: $hash"
Write-Output "Build logs: $runRoot"
