#Requires -Version 5.1
<#
.SYNOPSIS
Tests, checks, packages and publishes PsdUtil.

.EXAMPLE
./build.ps1                      # Test and Analyze

.EXAMPLE
./build.ps1 -Task Package        # dist/PsdUtil-<version>.zip

.EXAMPLE
$env:PSGALLERY_KEY = '...'; ./build.ps1 -Task Publish
#>
[CmdletBinding()]
param(
    [ValidateSet('Test', 'Analyze', 'Package', 'Publish')]
    [string[]] $Task = @('Test', 'Analyze'),

    # Skips code coverage, which is slow on Windows PowerShell.
    [switch] $NoCoverage
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$module = Join-Path $root 'src/PsdUtil'
$dist = Join-Path $root 'dist'
$version = (Import-PowerShellDataFile (Join-Path $module 'PsdUtil.psd1')).ModuleVersion
if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }

foreach ($t in $Task) {
    switch ($t) {
        'Test' {
            Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
            $c = New-PesterConfiguration
            $c.Run.Path = Join-Path $root 'tests'
            $c.Run.PassThru = $true
            $c.Output.Verbosity = 'Normal'
            $c.TestResult.Enabled = $true
            $c.TestResult.OutputPath = Join-Path $dist 'tests.xml'
            if (-not $NoCoverage) {
                $c.CodeCoverage.Enabled = $true
                $c.CodeCoverage.Path = $module
                $c.CodeCoverage.OutputPath = Join-Path $dist 'coverage.xml'
            }
            $r = Invoke-Pester -Configuration $c
            if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) tests failed." }
        }
        'Analyze' {
            Import-Module PSScriptAnalyzer -ErrorAction Stop
            $found = @(Invoke-ScriptAnalyzer -Path $module -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1'))
            if ($found.Count -gt 0) {
                $found | Format-Table RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
                throw "PSScriptAnalyzer found $($found.Count) problems."
            }
            Write-Host 'PSScriptAnalyzer: no problems.'
        }
        'Package' {
            $stage = Join-Path $dist 'package'
            if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
            New-Item -ItemType Directory -Path $stage | Out-Null
            Copy-Item -Recurse $module (Join-Path $stage 'PsdUtil')
            Copy-Item (Join-Path $root 'install.ps1') $stage
            $zip = Join-Path $dist "PsdUtil-$version.zip"
            if (Test-Path $zip) { Remove-Item -Force $zip }
            Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
            Remove-Item -Recurse -Force $stage
            Write-Host "Wrote $zip"
        }
        'Publish' {
            if (-not $env:PSGALLERY_KEY) { throw 'Set $env:PSGALLERY_KEY to publish.' }
            Publish-Module -Path $module -NuGetApiKey $env:PSGALLERY_KEY
            Write-Host "Published PsdUtil $version."
        }
    }
}
