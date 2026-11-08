BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    $script:c = Import-Text "@{ Server = @{ Tls = @{ Port = 2 } }; Plugins = @('a', 'b') }"
}

Describe 'Get-PsdValue' {
    It 'reads a nested path' {
        Get-PsdValue $c -Path 'Server.Tls.Port' | Should -Be 2
    }

    It 'reads a list item, counting from the end' {
        Get-PsdValue $c -Path 'Plugins[-1]' | Should -Be 'b'
    }
}
