#Requires -Version 5.1
<#
.SYNOPSIS
Installs PsdUtil for the current user.

.DESCRIPTION
Copies the module into the user's module folder, so Import-Module PsdUtil works anywhere.
On Windows it installs for both Windows PowerShell 5.1 and PowerShell 7.
On Linux and macOS it installs for PowerShell 7.

Works from the release zip (install.ps1 next to a PsdUtil folder) and from the repository.
#>
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'PsdUtil'
if (-not (Test-Path (Join-Path $source 'PsdUtil.psd1'))) { $source = Join-Path $PSScriptRoot 'src/PsdUtil' }
if (-not (Test-Path (Join-Path $source 'PsdUtil.psd1'))) { throw "Can't find PsdUtil.psd1 next to this script or in src/PsdUtil." }
$version = (Import-PowerShellDataFile (Join-Path $source 'PsdUtil.psd1')).ModuleVersion

$onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$targets = @()
if ($onWindows) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $targets += Join-Path $docs 'WindowsPowerShell/Modules'
    $targets += Join-Path $docs 'PowerShell/Modules'
}
else {
    $targets += Join-Path $HOME '.local/share/powershell/Modules'
}

foreach ($t in $targets) {
    $dest = Join-Path $t "PsdUtil/$version"
    if ($PSCmdlet.ShouldProcess($dest, 'Install PsdUtil')) {
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -Recurse -Path (Join-Path $source '*') -Destination $dest
        Write-Host "Installed PsdUtil $version to $dest"
    }
}
