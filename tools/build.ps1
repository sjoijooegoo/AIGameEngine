param([switch]$DebugBuild, [string]$Project = 'sandbox', [string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'engine/tools/build.ps1') @PSBoundParameters
