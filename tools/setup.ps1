param([switch]$ExportTemplates)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $root 'engine/tools/setup.ps1') @PSBoundParameters
