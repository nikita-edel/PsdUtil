<#
.SYNOPSIS
    Builds the module and writes out/<Name>-<Version>.zip, which installs offline.

.DESCRIPTION
    The zip holds <Name>/<Version>/ and install.ps1. To install: unzip it, then run ./install.ps1.
    Returns the path of the zip.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$outputRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'out'
$module = & (Join-Path $PSScriptRoot 'build.ps1')

$staging = Join-Path $outputRoot 'package'
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
$moduleTarget = Join-Path (Join-Path $staging $module.Name) $module.Version
$null = New-Item -ItemType Directory -Force -Path $moduleTarget
Copy-Item -Path (Join-Path $module.Path '*') -Destination $moduleTarget -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') -Destination $staging

$zip = Join-Path $outputRoot "$($module.Name)-$($module.Version).zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
# ZipFile writes '/' separators; Compress-Archive of Windows PowerShell 5.1 writes '\', which breaks on Linux.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zip)
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "Packaged $zip"
$zip
