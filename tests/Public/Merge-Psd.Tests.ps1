BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Merging' {
    It 'Merge-Psd merges files and maps, and -Key returns only those keys' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ A = 1; Paths = @{ Root = 'r' }; Logging = @{ File = '!<Paths.Root>/x.log' } }" }
        $m = Merge-Psd (Join-Path $dir 'a.psd1'), @{ A = 2; 'L +=' = @('x') }
        $m.A | Should -Be 2
        $m.L -join ',' | Should -Be 'x'
        $k = Merge-Psd (Join-Path $dir 'a.psd1') -Key Logging
        @($k.Keys) -join ',' | Should -Be 'Logging'
        $k.Logging.File | Should -Be 'r/x.log'
    }
}

Describe '-Include' {
    BeforeAll {
        $script:run = @{ run = @{ Stage = 'prod'; Root = 'C:\app' } }
        $script:app = "@{ Log = '!<run::Root>\log'; '!if !<run::Stage> -eq `"prod`"' = @{ Replicas = 3 } }"
    }

    It 'Merge-Psd takes it too' {
        $m = Merge-Psd @{ A = 1 }, @{ Log = '!<run::Root>' } -Include $run
        $m.Log | Should -Be 'C:\app'
    }
}

Describe "'!name' in maps" {
    It 'names the map in errors' {
        $dir = New-TestFiles @{}
        $named = Get-ErrorText { Merge-Psd @{ '!name' = 'team'; A = '!<Nope>' } } $dir
        "$named" | Should -Match '^team: '
    }

    It 'leaves a map without a name as input N' {
        $dir = New-TestFiles @{}
        "$(Get-ErrorText { Merge-Psd @{ A = '!<Nope>' } } $dir)" | Should -Match '^the input 1: '
    }

    It 'makes name::Key work, before merging' {
        $m = Merge-Psd @{ '!name' = 'team'; Port = 1 }, @{ Port = 2; Old = '!<team::Port>' }
        $m.Old | Should -Be 1
        $m.Port | Should -Be 2
    }

    It 'makes this:: work' {
        (Merge-Psd @{ '!name' = 'team'; P = 1; O = '!<this::@name>' }, @{ P = 2 }).O | Should -Be 'team'
    }

    It 'makes @name the last named input, like a file' {
        $dir = New-TestFiles @{ 'base.psd1' = "@{ N = '!<@name>' }" }
        $f = Join-Path $dir 'base.psd1'
        (Merge-Psd $f, @{ '!name' = 'team' }).N | Should -Be 'team'
        (Merge-Psd @{ '!name' = 'team' }, $f).N | Should -Be 'base'
    }

    It 'is not a key in the result' {
        @((Merge-Psd @{ '!name' = 'team'; A = 1 }).Keys) -join ',' | Should -Be 'A'
    }

    It 'keeps <Key> an error in a map' -ForEach @(
        @{ Key = '!merge' }, @{ Key = '!include' }, @{ Key = '!schema' }, @{ Key = '!types' }
    ) {
        $dir = New-TestFiles @{ 'x.psd1' = '@{}' }
        $map = @{ $Key = './x.psd1' }
        $codes = @(Get-ErrorCode { Merge-Psd $map } $dir)
        ($codes -contains 'PSD206' -or $codes -contains 'PSD205') | Should -BeTrue
    }

    It 'is only allowed at the top of a Merge-Psd map' {
        $dir = New-TestFiles @{ 'app.psd1' = '@{ A = 1 }' }
        Get-ErrorCode { Merge-Psd @{ A = @{ '!name' = 'x' } } } $dir | Should -Contain 'PSD206'
        Get-ErrorCode { Import-Psd ./app.psd1 -Override @{ '!name' = 'x' } } $dir | Should -Contain 'PSD206'
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ run = @{ '!name' = 'x' } } } $dir | Should -Contain 'PSD206'
    }

    It 'follows the rules for names' {
        $dir = New-TestFiles @{ 'team.psd1' = '@{}' }
        Get-ErrorCode { Merge-Psd @{ '!name' = 'this' } } $dir | Should -Contain 'PSD204'
        Get-ErrorCode { Merge-Psd @{ '!name' = 'a b' } } $dir | Should -Contain 'PSD206'
        Get-ErrorCode { Merge-Psd @{ '!name' = 'x'; A = 1 }, @{ '!name' = 'x'; B = 1 } } $dir | Should -Contain 'PSD203'
        Get-ErrorCode { Merge-Psd ./team.psd1, @{ '!name' = 'team' } } $dir | Should -Contain 'PSD203'
    }
}

Describe 'Merge-Psd -Schema' {
    BeforeAll {
        $script:schema = "@{ Properties = @{ Port = @{ Type = 'int'; Description = 'TCP port.' }; Name = @{ Type = 'string'; Required = `$true } } }"
    }

    It 'returns the result when it fits' {
        $dir = New-TestFiles @{ 's.psd1' = $schema }
        (Merge-Psd @{ Port = 1 }, @{ Name = 'x' } -Schema (Join-Path $dir 's.psd1')).Port | Should -Be 1
    }

    It 'keeps the file and line, with the same message as Import-Psd' {
        $dir = New-TestFiles @{ 's.psd1' = $schema; 'a.psd1' = "@{`n    Name = 'x'`n    Port = 'abc'`n}" }
        $imported = Get-ErrorText { Import-Psd ./a.psd1 -Schema ./s.psd1 } $dir
        $merged = Get-ErrorText { Merge-Psd ./a.psd1 -Schema ./s.psd1 } $dir
        "$merged" | Should -Be "$imported"
        "$merged" | Should -Match 'a\.psd1, line 3'
        "$merged" | Should -Match 'PSD501'
        "$merged" | Should -Match 'TCP port\.'
    }

    It 'names a map with !name in the message' {
        $dir = New-TestFiles @{ 's.psd1' = $schema; 'base.psd1' = "@{ Name = 'x' }" }
        $t = Get-ErrorText { Merge-Psd ./base.psd1, @{ '!name' = 'team'; Port = 'abc' } -Schema ./s.psd1 } $dir
        "$t" | Should -Match '^team: Port has to be'
    }

    It 'returns nothing when it does not fit' {
        $dir = New-TestFiles @{ 's.psd1' = $schema }
        $r = Merge-Psd @{ Port = 'abc'; Name = 'x' } -Schema (Join-Path $dir 's.psd1') -ErrorAction SilentlyContinue
        $r | Should -BeNullOrEmpty
    }

    It 'checks the whole merge when -Key limits the result' {
        $dir = New-TestFiles @{ 's.psd1' = $schema }
        Get-ErrorCode { Merge-Psd @{ Port = 1 } -Key Port -Schema ./s.psd1 } $dir | Should -Contain 'PSD502'
        $r = Merge-Psd @{ Port = 1; Name = 'x' } -Key Port -Schema (Join-Path $dir 's.psd1')
        @($r.Keys) -join ',' | Should -Be 'Port'
    }

    It 'gives PSD511 for a missing schema file' {
        $dir = New-TestFiles @{}
        Get-ErrorCode { Merge-Psd @{ A = 1 } -Schema ./nope.psd1 } $dir | Should -Contain 'PSD511'
    }
}
