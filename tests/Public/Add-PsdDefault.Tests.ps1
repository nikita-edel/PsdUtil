BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Schema' {
    It 'Add-PsdDefault fills in missing keys only' {
        $dir = New-TestFiles @{ 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Default = 3 }; B = @{ Type = 'int'; Default = 4 } } }" }
        $o = [ordered]@{ B = 1 }
        Add-PsdDefault $o -Schema (Join-Path $dir 's.psd1')
        $o.A | Should -Be 3
        $o.B | Should -Be 1
    }
}
