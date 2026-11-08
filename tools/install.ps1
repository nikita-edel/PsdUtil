<#
.SYNOPSIS
    Installs the module for the current user, without internet access.

.DESCRIPTION
    Copies <Name>/<Version>/ from the folder next to this script into the current user's module folder(s), so
    that 'Import-Module <Name>' works in new sessions. On Windows that is both Windows PowerShell 5.1
    (Documents\WindowsPowerShell\Modules) and PowerShell 7 (Documents\PowerShell\Modules); on Linux and macOS
    ~/.local/share/powershell/Modules. An installed copy of the same version is replaced.

.PARAMETER SourcePath
    Folder that holds <Name>/<Version>/. Defaults to the folder of this script, which is right for the release zip.

.PARAMETER ModulePath
    Module folder(s) to use instead of the default ones.

.PARAMETER Uninstall
    Remove this version again.

.EXAMPLE
    ./install.ps1

.EXAMPLE
    ./install.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCmdlets', '', Justification = 'Unblock-File is only called on Windows.')]
[CmdletBinding()]
param(
    [string]$SourcePath = $PSScriptRoot,
    [string[]]$ModulePath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# <Name>/<Version>/<Name>.psd1
$manifests = @(
    Get-ChildItem -LiteralPath $SourcePath -Directory | Get-ChildItem -Directory | Get-ChildItem -File -Filter '*.psd1' |
        Where-Object { $_.BaseName -eq $_.Directory.Parent.Name }
)
if ($manifests.Count -ne 1) { throw "Expected one module in $SourcePath (<Name>/<Version>/<Name>.psd1), found $($manifests.Count). From the repository, use ./build.ps1 -Install." }
$moduleName = $manifests[0].BaseName
$version = $manifests[0].Directory.Name

$roots = $ModulePath
if (-not $roots) {
    # $IsWindows does not exist in Windows PowerShell 5.1; -or stops before reading it there.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) {
        $documents = [Environment]::GetFolderPath('MyDocuments')
        $roots = @((Join-Path $documents 'PowerShell/Modules'), (Join-Path $documents 'WindowsPowerShell/Modules'))
    }
    else {
        $dataHome = $env:XDG_DATA_HOME
        if (-not $dataHome) { $dataHome = Join-Path $HOME '.local/share' }
        $roots = @(Join-Path $dataHome 'powershell/Modules')
    }
}

foreach ($root in $roots) {
    $moduleRoot = Join-Path $root $moduleName
    $target = Join-Path $moduleRoot $version
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    if ($Uninstall) {
        if ((Test-Path -LiteralPath $moduleRoot) -and @(Get-ChildItem -LiteralPath $moduleRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $moduleRoot -Force }
        Write-Host "Removed $moduleName $version from $root"
        continue
    }
    $null = New-Item -ItemType Directory -Force -Path $target
    Copy-Item -Path (Join-Path $manifests[0].Directory.FullName '*') -Destination $target -Recurse -Force
    # Files from a downloaded zip are marked as coming from the internet, which blocks them under RemoteSigned.
    # Unblock-File exists in PowerShell on Linux and macOS too, but fails there.
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File }
    Write-Host "Installed $moduleName $version to $target"
}
if (-not $Uninstall) { Write-Host "In a new session: Import-Module $moduleName" }
