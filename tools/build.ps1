<#
.SYNOPSIS
    Stages the module in out/<Name>/<Version> and returns its name, version and path.

.DESCRIPTION
    The module is the one folder in src/, which holds <Name>.psd1. Install, Package and Publish all work
    from this staged copy, which also carries LICENSE, README.md and CHANGELOG.txt.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

$sources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)
if ($sources.Count -ne 1) { throw "Expected exactly one module folder in src/, found $($sources.Count)." }
$source = $sources[0]
$moduleName = $source.Name
$sourceManifest = Join-Path $source.FullName "$moduleName.psd1"
if (-not (Test-Path -LiteralPath $sourceManifest)) { throw "Missing manifest: $sourceManifest" }
$version = [string](Import-PowerShellDataFile -Path $sourceManifest).ModuleVersion

$moduleRoot = Join-Path (Join-Path $repoRoot 'out') $moduleName
$target = Join-Path $moduleRoot $version
if (Test-Path -LiteralPath $moduleRoot) { Remove-Item -LiteralPath $moduleRoot -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $target

Copy-Item -Path (Join-Path $source.FullName '*') -Destination $target -Recurse -Force
foreach ($extra in @('LICENSE', 'README.md', 'CHANGELOG.txt')) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $extra) -Destination $target
}

$null = Test-ModuleManifest -Path (Join-Path $target "$moduleName.psd1")
Write-Host "Built $target"

[pscustomobject]@{
    Name    = $moduleName
    Version = $version
    Path    = $target
}
