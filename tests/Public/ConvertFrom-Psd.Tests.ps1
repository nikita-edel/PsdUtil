BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Files' {
    It 'ConvertFrom-Psd uses -BasePath for relative paths' {
        $dir = New-TestFiles @{ 'base.psd1' = '@{ A = 1 }' }
        (ConvertFrom-Psd -Text "@{ '!merge' = './base.psd1'; B = '!<A>' }" -BasePath $dir).B | Should -Be 1
    }
}

Describe '-Include' {
    BeforeAll {
        $script:run = @{ run = @{ Stage = 'prod'; Root = 'C:\app' } }
        $script:app = "@{ Log = '!<run::Root>\log'; '!if !<run::Stage> -eq `"prod`"' = @{ Replicas = 3 } }"
    }

    It 'ConvertFrom-Psd takes it too' {
        (ConvertFrom-Psd -Text $app -Include $run).Log | Should -Be 'C:\app\log'
    }
}
