BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Debug commands' {
    It 'Get-PsdProvenance shows source and overrides' {
        $p = Get-PsdProvenance (Join-Path $Examples 'config/last.psd1') -Key 'Server.Port'
        $p.Value | Should -Be 9000
        $p.Source | Should -Be 'next.psd1:5:24'
        $p.Overrides | Should -Be 'base.psd1:19:16'
    }
}
