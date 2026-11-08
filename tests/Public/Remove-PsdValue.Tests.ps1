BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Remove-PsdValue' {
    BeforeEach { $script:c = Import-Text "@{ Token = 't'; Plugins = @('a', 'b') }" }

    It 'removes a key' {
        Remove-PsdValue $c -Path 'Token'
        $c.Contains('Token') | Should -BeFalse
    }

    It 'removes a list item' {
        Remove-PsdValue $c -Path 'Plugins[0]'
        $c.Plugins -join ',' | Should -Be 'b'
    }
}
