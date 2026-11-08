BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    $script:c = Import-Text "@{ Stage = 'dev'; Server = @{ Port = 1 } }"
}

Describe 'Get-PsdMissingKey' {
    It 'returns the keys that do not exist' {
        Get-PsdMissingKey $c -Key Stage, Nope, 'Server.Nope' | Should -Be @('Nope', 'Server.Nope')
    }

    It 'returns nothing when all exist' {
        Get-PsdMissingKey $c -Key Stage, 'Server.Port' | Should -BeNullOrEmpty
    }
}
