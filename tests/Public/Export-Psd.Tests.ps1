BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Writing' {
    It 'Export-Psd writes UTF-8 without BOM by default' {
        $p = Join-Path $TestDrive 'out.psd1'
        Export-Psd @{ A = "$([char]0xE4)" } -Path $p
        $bytes = [IO.File]::ReadAllBytes($p)
        $bytes[0] | Should -Be ([byte][char]'@')
        (Import-Psd $p).A | Should -Be ([string][char]0xE4)
    }
}

Describe 'Generated classes keep their map' {
    BeforeAll {
        $schemaText = @"
@{
    Properties = @{
        Name     = 'string'
        Url      = 'string'
        Host     = 'string'
        Stage    = 'string'
        Replicas = 'int'
        Plugins  = 'string[]'
        Server   = @{ Type = 'map'; Properties = @{ Host = 'string'; Port = 'int'; Tags = 'string[]' } }
        Backups  = @{ Type = 'array'; Items = @{ Type = 'map'; Properties = @{ Host = 'string' } } }
    }
}
"@
        $script:typesDir = New-TestFiles @{ 's.psd1' = $schemaText }
        $script:mod = Join-Path $typesDir 'App.Types.psm1'
        New-PsdType -Schema (Join-Path $typesDir 's.psd1') -Path $mod -Name App

        function Invoke-Typed {
            param([string] $Body)
            & ([scriptblock]::Create("using module '$mod'`n$Body"))
        }

        $script:goal = @'
[App][ordered]@{
    Name = 'billing'
    Host = 'h'
    Url  = 'http://!<Host>'
    'Plugins +=' = @('cache')
    '!if !<Stage> -eq "prod"' = @{ Replicas = 3 }
}
'@
    }

    It 'Export-Psd writes a file that loads like a data file' {
        $file = Join-Path $TestDrive 'typed.psd1'
        Export-Psd -InputObject (Invoke-Typed $goal) -Path $file
        $r = Import-Psd $file -Override @{ Stage = 'prod' }
        $r.Url | Should -Be 'http://h'
        $r.Plugins -join ',' | Should -Be 'cache'
        $r.Replicas | Should -Be 3
    }
}
