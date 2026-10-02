param([switch]$ExportTemplates)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = '4.7.2'
$dir = Join-Path $root '.tools'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$sums = Join-Path $dir 'SHA512-SUMS.txt'
$release = "https://github.com/godotengine/godot-builds/releases/download/$version-stable"
if (!(Test-Path -LiteralPath $sums)) { Invoke-WebRequest "$release/SHA512-SUMS.txt" -OutFile $sums }
function Get-VerifiedArchive($name, $url, $destination) {
    if (!(Test-Path -LiteralPath $destination)) { Invoke-WebRequest $url -OutFile $destination }
    $line = Get-Content -LiteralPath $sums | Where-Object { $_ -match ([regex]::Escape($name) + '$') } | Select-Object -First 1
    if (!$line) { throw "Missing official checksum for $name" }
    $expected = ($line -split '\s+')[0]
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA512).Hash
    if ($actual -ine $expected) { throw "Checksum mismatch: $destination. Remove this archive and retry." }
}
$exe = Join-Path $dir "Godot_v$version-stable_win64_console.exe"
Get-VerifiedArchive "Godot_v$version-stable_win64.exe.zip" "https://downloads.godotengine.org/?version=$version&flavor=stable&slug=win64.exe.zip&platform=windows.64" (Join-Path $dir 'godot.zip')
if (!(Test-Path -LiteralPath $exe)) { Expand-Archive -LiteralPath (Join-Path $dir 'godot.zip') -DestinationPath $dir -Force }
if ($ExportTemplates) {
    $name = "Godot_v$version-stable_export_templates.tpz"
    $archive = Join-Path $dir $name
    Get-VerifiedArchive $name "$release/$name" $archive
    # Extract only Windows x86_64 templates into this workspace, not the global user profile.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    $target = Join-Path $dir 'templates'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.Name -in @('windows_debug_x86_64.exe','windows_release_x86_64.exe')) {
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $target $entry.Name), $true)
            }
        }
    } finally { $zip.Dispose() }
}
& $exe --version
python -m pip install -r (Join-Path $root 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Python dependency installation failed' }
& $exe --headless --path (Join-Path $root 'game') --editor --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
