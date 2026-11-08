<#
.SYNOPSIS
    Test, install, package and publish this module.

.DESCRIPTION
    Several actions can be combined; they run in the order Test, Package, Install, Publish.

.PARAMETER Test
    Run the Pester tests. Names after -Test select what runs: a test name, or a path to a test file or folder.

.PARAMETER TestName
    The tests to run. Given positionally, after -Test.

.PARAMETER Install
    Build the module and run tools/install.ps1 to install it for the current user.

.PARAMETER ModulePath
    With -Install: module folder(s) to use instead of the current user's default ones.

.PARAMETER Package
    Write out/<Name>-<Version>.zip: the module and an install.ps1 that installs it offline.

.PARAMETER Publish
    The PowerShell Gallery API key. Builds the module and publishes it.

.PARAMETER Repository
    With -Publish: the repository to publish to.

.EXAMPLE
    ./build.ps1 -Test
    Runs all tests.

.EXAMPLE
    ./build.ps1 -Test Import-Psd tests/Errors.Tests.ps1
    Runs tests/Public/Import-Psd.Tests.ps1 and tests/Errors.Tests.ps1.

.EXAMPLE
    ./build.ps1 -Install

.EXAMPLE
    ./build.ps1 -Package

.EXAMPLE
    ./build.ps1 -Publish $env:PSGALLERY_API_KEY
#>
[CmdletBinding()]
param(
    [switch]$Test,

    # object[], not string[]: -Test a,b arrives here as one array, which string[] would join into 'a b'.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [object[]]$TestName,

    [switch]$Install,

    [string[]]$ModulePath,

    [switch]$Package,

    [string]$Publish,

    [string]$Repository = 'PSGallery'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$tools = Join-Path $PSScriptRoot 'tools'
$names = @($TestName | ForEach-Object { $_ } | Where-Object { $_ } | ForEach-Object { [string]$_ })
$wantsPublish = $PSBoundParameters.ContainsKey('Publish')

if ($names.Count -gt 0 -and -not $Test) { throw "Unexpected argument(s): $($names -join ' '). Test names go after -Test." }
if ($wantsPublish -and [string]::IsNullOrWhiteSpace($Publish)) { throw 'The API key given to -Publish is empty.' }
if ($wantsPublish -and -not (Get-Command -Name Publish-PSResource -ErrorAction SilentlyContinue)) {
    throw 'Publishing needs PSResourceGet, which comes with PowerShell 7.4 and later. Use pwsh, or: Install-Module Microsoft.PowerShell.PSResourceGet -Scope CurrentUser'
}
if (-not ($Test -or $Install -or $Package -or $wantsPublish)) {
    Get-Help -Name $PSCommandPath
    return
}

if ($Test) {
    # A process of its own: a profile's aliases or an installed copy of the module cannot interfere with the tests.
    $command = "& '$((Join-Path $tools 'test.ps1') -replace "'", "''")'"
    if ($names.Count -gt 0) { $command += ' -Name ' + (@($names | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ',') }
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -Command $command
    if ($LASTEXITCODE -ne 0) { throw 'The tests failed; see the output above.' }
}

if ($Package) {
    $null = & (Join-Path $tools 'package.ps1')
}

if ($Install) {
    $module = & (Join-Path $tools 'build.ps1')
    $installArguments = @{ SourcePath = Split-Path -Parent (Split-Path -Parent $module.Path) }
    if ($ModulePath) { $installArguments.ModulePath = $ModulePath }
    & (Join-Path $tools 'install.ps1') @installArguments
}

if ($wantsPublish) {
    $module = & (Join-Path $tools 'build.ps1')
    # Not Publish-Module: it needs nuget or dotnet, and parses nuget's English output, so it fails on other locales.
    Publish-PSResource -Path $module.Path -ApiKey $Publish -Repository $Repository -ErrorAction Stop
    Write-Host "Published $($module.Name) $($module.Version) to $Repository"
}
