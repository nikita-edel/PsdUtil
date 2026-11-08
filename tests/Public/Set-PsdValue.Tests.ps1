BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Set-PsdValue' {
    BeforeEach { $script:c = Import-Text "@{ Server = @{ Port = 1 } }" }

    It 'changes a value' {
        Set-PsdValue $c -Path 'Server.Port' -Value 9
        $c.Server.Port | Should -Be 9
    }

    It 'creates missing maps on the way' {
        Set-PsdValue $c -Path 'New.Deep' -Value 'x'
        $c.New.Deep | Should -Be 'x'
    }
}
