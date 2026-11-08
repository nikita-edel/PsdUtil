# Meta tests: rules that hold for the whole module, whatever it contains.
#   * the manifest is valid and exports exactly the functions in Public/
#   * every public function has comment-based help with an example
#   * all source and test files are ASCII (Windows PowerShell 5.1 reads BOM-less files as ANSI)
#   * PSScriptAnalyzer reports nothing (skipped if it is not installed)

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $moduleFolder = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)[0].FullName
    $script:publicCases = @(
        Get-ChildItem -LiteralPath (Join-Path $moduleFolder 'Public') -Filter '*.ps1' -Recurse | ForEach-Object { @{ Name = $_.BaseName } }
    )
    $script:fileCases = @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src'), (Join-Path $repoRoot 'tests'), (Join-Path $repoRoot 'tools') -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
            Where-Object { -not $_.PSIsContainer } |   # Windows PowerShell 5.1 also returns directories here
            ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($repoRoot.Length + 1) } }
    )
    $script:analyzerMissing = $null -eq (Get-Module -ListAvailable -Name PSScriptAnalyzer)
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $script:manifestData = Import-PowerShellDataFile -Path $TestManifest
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $TestManifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7 (Desktop and Core)' {
        $manifestData.PowerShellVersion | Should -Be '5.1'
        $manifestData.CompatiblePSEditions | Should -Be @('Desktop', 'Core')
    }

    It 'exports exactly the functions in Public/' {
        $expected = @(Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $TestManifest) 'Public') -Filter '*.ps1' -Recurse | ForEach-Object { $_.BaseName } | Sort-Object)
        @($manifestData.FunctionsToExport | Sort-Object) | Should -Be $expected
        @((Get-Module $TestModuleName).ExportedFunctions.Keys | Sort-Object) | Should -Be $expected
    }
}

Describe 'Public function <Name>' -ForEach $publicCases {
    It 'has comment-based help with an example' {
        @((Get-Help -Name $Name -Full).Examples.Example).Count | Should -BeGreaterThan 0
    }
}

Describe 'Source file <Name>' -ForEach $fileCases {
    It 'is ASCII only' {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'PSScriptAnalyzer' -Skip:$analyzerMissing {
    It 'reports nothing for src/, tools/ and build.ps1' {
        $settings = Join-Path $TestRepoRoot 'PSScriptAnalyzerSettings.psd1'
        $findings = foreach ($path in @('src', 'tools', 'build.ps1')) {
            Invoke-ScriptAnalyzer -Path (Join-Path $TestRepoRoot $path) -Recurse -Settings $settings
        }
        @($findings | ForEach-Object { "$($_.ScriptName):$($_.Line) $($_.RuleName): $($_.Message)" }) | Should -BeNullOrEmpty
    }
}
