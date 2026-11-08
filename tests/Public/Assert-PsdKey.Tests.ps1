BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
    $script:c = Import-Text "@{ Stage = 'dev' }"
}

Describe 'Assert-PsdKey' {
    It 'throws and names the missing keys' {
        { Assert-PsdKey $c -Key Stage, Nope } | Should -Throw '*Nope*'
    }

    It 'does nothing when all exist' {
        { Assert-PsdKey $c -Key Stage } | Should -Not -Throw
    }
}
