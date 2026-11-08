<#
.SYNOPSIS
    Runs the Pester tests. Use ./build.ps1 -Test, which starts this in a process without a profile.

.PARAMETER Name
    Tests to run: a test name (Import-Psd, wildcards allowed) or a path to a test file or folder.
    Without it, everything in tests/ runs.
#>
[CmdletBinding()]
param(
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests'
$pesterMinimumVersion = [version]'5.5.0'

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge $pesterMinimumVersion })) {
    throw "Pester >= $pesterMinimumVersion is required: Install-Module Pester -MinimumVersion $pesterMinimumVersion -Scope CurrentUser -SkipPublisherCheck -Force"
}
Import-Module Pester -MinimumVersion $pesterMinimumVersion

$paths = @($testsDir)
if ($Name) {
    $paths = @(foreach ($item in $Name) {
            if (Test-Path -LiteralPath $item) {
                (Resolve-Path -LiteralPath $item).ProviderPath
                continue
            }
            $found = @(Get-ChildItem -LiteralPath $testsDir -Recurse -File -Filter "$item.Tests.ps1")
            if ($found.Count -eq 0) { throw "No test matches '$item'." }
            $found.FullName
        })
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $paths
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

# Tests capture errors with 2>&1, which 'Stop' would turn into exceptions.
$ErrorActionPreference = 'Continue'
$result = Invoke-Pester -Configuration $configuration
if ($result.Result -ne 'Passed') { throw "$($result.FailedCount) test(s) failed." }
