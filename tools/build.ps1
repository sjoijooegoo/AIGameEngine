param([switch]$DebugBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools/Godot_v4.7.2-stable_win64_console.exe'
if ($env:GODOT_BIN) { $exe = $env:GODOT_BIN }
$template = Join-Path $root '.tools/templates/windows_release_x86_64.exe'
if (!(Test-Path -LiteralPath $template)) { throw 'Run tools/setup.ps1 -ExportTemplates first.' }
$out = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$mode = if ($DebugBuild) { '--export-debug' } else { '--export-release' }
& $exe --headless --path (Join-Path $root 'game') $mode 'Windows Desktop' (Join-Path $out 'BankCrisisLab.exe')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
Copy-Item -LiteralPath (Join-Path $root 'third_party/GODOT-LICENSE.txt') -Destination (Join-Path $out 'GODOT-LICENSE.txt') -Force
Write-Output (Join-Path $out 'BankCrisisLab.exe')
