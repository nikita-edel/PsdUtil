BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Debug commands' {
    It 'Compare-Psd lists changes' {
        $d = Compare-Psd @{ A = 1; B = @(1, 2); C = 'x' } @{ A = 2; B = @(1); D = 'y' }
        ($d | Where-Object Path -eq 'A').Change | Should -Be 'changed'
        ($d | Where-Object Path -eq 'B[1]').Change | Should -Be 'removed'
        ($d | Where-Object Path -eq 'C').Change | Should -Be 'removed'
        ($d | Where-Object Path -eq 'D').Change | Should -Be 'added'
    }
}
