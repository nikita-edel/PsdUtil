BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Schema' {
    It 'New-PsdSchema infers types' {
        $s = New-PsdSchema -InputObject ([ordered]@{ A = 1; L = @('x'); M = @{ B = $true } })
        $s.Properties.A | Should -Be 'int'
        $s.Properties.L | Should -Be 'string[]'
        $s.Properties.M.Properties.B | Should -Be 'bool'
    }
}
