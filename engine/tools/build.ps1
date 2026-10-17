param([switch]$DebugBuild, [string]$Project = 'sandbox', [string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$python = Join-Path $root '.venv/Scripts/python.exe'
if (!(Test-Path -LiteralPath $python)) { throw 'Run engine/tools/setup.ps1 first' }
$arguments = @((Join-Path $root 'engine/run.py'), '--project', $Project, 'build')
if ($DebugBuild) { $arguments += '--debug' }
if ($Version) { $arguments += @('--version', $Version) }
& $python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed' }
