BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    $script:c = Import-Text "@{ Stage = 'dev'; Server = @{ Port = 1; Tls = @{ Enabled = `$true; Port = 2 } } }"
}

Describe 'Test-PsdKey' {
    It 'checks keys and nested paths' {
        Test-PsdKey $c -Key Stage, 'Server.Port' | Should -BeTrue
        Test-PsdKey $c -Key Stage, Nope | Should -BeFalse
    }

    It 'checks that no other keys exist with -Exact' {
        Test-PsdKey $c.Server.Tls -Key Enabled, Port -Exact | Should -BeTrue
        Test-PsdKey $c.Server -Key Port -Exact | Should -BeFalse
    }

    It 'needs one key with -Any' {
        Test-PsdKey $c -Key Foo, Stage -Any | Should -BeTrue
    }

    It 'ignores case unless -CaseSensitive is given' {
        Test-PsdKey $c -Key stage | Should -BeTrue
        Test-PsdKey $c -Key stage -CaseSensitive | Should -BeFalse
    }
}
