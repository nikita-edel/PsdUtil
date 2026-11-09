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

Describe 'Operators with an index' {
    It 'with <Key> = <Value> gives <Expected>' -ForEach @(
        @{ Key = 'X[1] :='; Value = "'y'"; Expected = 'a,y,c,d' }
        @{ Key = 'X[0] :='; Value = "'y'"; Expected = 'y,b,c,d' }
        @{ Key = 'X[3] :='; Value = "'y'"; Expected = 'a,b,c,y' }
        @{ Key = 'X[-1] :='; Value = "'y'"; Expected = 'a,b,c,y' }
        @{ Key = 'X[-4] :='; Value = "'y'"; Expected = 'y,b,c,d' }
        @{ Key = 'X[1] -='; Value = '$true'; Expected = 'a,c,d' }
        @{ Key = 'X[0] -='; Value = '$true'; Expected = 'b,c,d' }
        @{ Key = 'X[-1] -='; Value = '$true'; Expected = 'a,b,c' }
        @{ Key = 'X[-4] -='; Value = '$true'; Expected = 'b,c,d' }
        @{ Key = 'X[0] +='; Value = "'y'"; Expected = 'y,a,b,c,d' }
        @{ Key = 'X[1] +='; Value = "'y'"; Expected = 'a,y,b,c,d' }
        @{ Key = 'X[3] +='; Value = "'y'"; Expected = 'a,b,c,y,d' }
        @{ Key = 'X[4] +='; Value = "'y'"; Expected = 'a,b,c,d,y' }
        @{ Key = 'X[69] +='; Value = "'y'"; Expected = 'a,b,c,d,y' }
        @{ Key = 'X[99999999999] +='; Value = "'y'"; Expected = 'a,b,c,d,y' }
        @{ Key = 'X[-1] +='; Value = "'y'"; Expected = 'a,b,c,d,y' }
        @{ Key = 'X[-2] +='; Value = "'y'"; Expected = 'a,b,c,y,d' }
        @{ Key = 'X[-5] +='; Value = "'y'"; Expected = 'y,a,b,c,d' }
        @{ Key = 'X[-69] +='; Value = "'y'"; Expected = 'y,a,b,c,d' }
        @{ Key = 'X[-99999999999] +='; Value = "'y'"; Expected = 'y,a,b,c,d' }
        @{ Key = 'X[1] +='; Value = "@('y', 'z')"; Expected = 'a,y,z,b,c,d' }
        @{ Key = 'X[-1] +='; Value = "@('y', 'z')"; Expected = 'a,b,c,d,y,z' }
        @{ Key = 'X[1] +='; Value = '@()'; Expected = 'a,b,c,d' }
    ) {
        $r = Import-Text "@{ X = @('a', 'b', 'c', 'd'); '$Key' = $Value }"
        $r.X -join ',' | Should -Be $Expected
    }

    It 'replaces an item with any kind of value' {
        $r = Import-Text "@{ X = @('a', 'b'); 'X[0] :=' = @{ N = 1 }; 'X[1] :=' = @(1, 2) }"
        $r.X[0].N | Should -Be 1
        $r.X[1] -join ',' | Should -Be '1,2'
        (Import-Text "@{ X = @('a', 'b'); 'X[0] :=' = `$null }").X[0] | Should -BeNullOrEmpty
    }

    It 'removing the only item leaves an empty list' {
        $r = Import-Text "@{ X = @('a'); 'X[0] -=' = `$true }"
        $r.Contains('X') | Should -BeTrue
        @($r.X).Count | Should -Be 0
    }

    It 'inserts into an empty list, a $null and a key that does not exist' {
        (Import-Text "@{ X = @(); 'X[5] +=' = 'y' }").X -join ',' | Should -Be 'y'
        (Import-Text "@{ X = @(); 'X[-1] +=' = 'y' }").X -join ',' | Should -Be 'y'
        (Import-Text "@{ X = `$null; 'X[0] +=' = 'y' }").X -join ',' | Should -Be 'y'
        (Import-Text "@{ 'X[3] +=' = @('y', 'z') }").X -join ',' | Should -Be 'y,z'
    }

    It 'runs top to bottom, each on the list the one before left' {
        $r = Import-Text "@{ X = @('a', 'b', 'c'); 'X[0] -=' = `$true; 'X[0] :=' = 'y'; 'X[-1] +=' = 'z' }"
        $r.X -join ',' | Should -Be 'y,c,z'
    }

    It 'works on the result of other operators' {
        $r = Import-Text "@{ X = @('a'); 'X +=' = @('b', 'c'); 'X[-1] :=' = 'y'; 'X =+' = @('s'); 'X[1] -=' = `$true }"
        $r.X -join ',' | Should -Be 's,b,y'
    }

    It 'works on a list from a reference' {
        $r = Import-Text "@{ Base = @('a', 'b'); X = '!<Base>'; 'X[1] :=' = 'y'; 'X[69] +=' = 'z' }"
        $r.X -join ',' | Should -Be 'a,y,z'
        $r.Base -join ',' | Should -Be 'a,b'
    }

    It 'takes references as values' {
        $r = Import-Text "@{ V = 'y'; X = @('a', 'b'); 'X[1] :=' = '!<V>'; 'X[0] +=' = '!<V>' }"
        $r.X -join ',' | Should -Be 'y,a,y'
    }

    It 'works inside an !if, only when it is true' {
        $text = "@{ T = 'VALUE'; X = @('a', 'b'); '!if !<T> -eq `"1`"' = @{ 'X[1] :=' = 'y'; 'X[0] -=' = `$true } }"
        (Import-Text $text.Replace('VALUE', '1')).X -join ',' | Should -Be 'y'
        (Import-Text $text.Replace('VALUE', '2')).X -join ',' | Should -Be 'a,b'
    }

    It 'works over a !merge and in nested maps' {
        $r = Import-Text "@{ '!merge' = './base.psd1'; 'X[1] :=' = 'y'; S = @{ 'L[-1] +=' = 'z' } }" -More @{ 'base.psd1' = "@{ X = @('a', 'b'); S = @{ L = @('l') } }" }
        $r.X -join ',' | Should -Be 'a,y'
        $r.S.L -join ',' | Should -Be 'l,z'
    }

    It 'works in maps given to Merge-Psd' {
        $m = Merge-Psd @{ X = @('a', 'b') }, @{ 'X[0] :=' = 'y' }
        $m.X -join ',' | Should -Be 'y,b'
    }

    It 'is checked by the schema, and a Merge in the schema does not change it' {
        $schema = "@{ Properties = @{ X = @{ Type = 'int[]'; Merge = '+=' } } }"
        $dir = New-TestFiles @{ 'bad.psd1' = "@{ X = @(1, 2); 'X[0] :=' = 'text' }"; 'good.psd1' = "@{ X = @(1, 2); 'X[0] :=' = 5 }"; 'a.schema.psd1' = $schema }
        Get-ErrorCode { Import-Psd ./bad.psd1 -Schema ./a.schema.psd1 } $dir | Should -Not -BeNullOrEmpty
        (Import-Psd (Join-Path $dir 'good.psd1') -Schema (Join-Path $dir 'a.schema.psd1')).X -join ',' | Should -Be '5,2'
    }

    It 'keeps keys that only look like an index as plain keys' {
        $r = Import-Text "@{ X = @('a'); 'X[1]' = 'p'; 'X[a] :=' = 'q'; 'Y [1] :=' = 'r' }"
        $r.X -join ',' | Should -Be 'a'
        $r['X[1]'] | Should -Be 'p'
        $r['X[a]'] | Should -Be 'q'
        $r['Y [1]'] | Should -Be 'r'
    }
}

Describe 'Operators with a value' {
    It 'with <Key> = <Value> gives <Expected>' -ForEach @(
        @{ Key = "'X[''b''] :='"; Value = "'y'"; Expected = 'a,y,a,c' }
        @{ Key = "'X[''a''] :='"; Value = "'y'"; Expected = 'y,b,y,c' }
        @{ Key = '"X[''a''] :="'; Value = "'y'"; Expected = 'y,b,y,c' }
        @{ Key = "'X[`"a`"] :='"; Value = "'y'"; Expected = 'y,b,y,c' }
        @{ Key = "'X[''A''] :='"; Value = "'y'"; Expected = 'y,b,y,c' }
        @{ Key = "'X[''b''] -='"; Value = '$true'; Expected = 'a,a,c' }
        @{ Key = "'X[''a''] -='"; Value = '$true'; Expected = 'b,c' }
        @{ Key = '"X[''c''] -="'; Value = '$true'; Expected = 'a,b,a' }
        @{ Key = "'X[`"b`"] -='"; Value = '$true'; Expected = 'a,a,c' }
    ) {
        $r = Import-Text "@{ X = @('a', 'b', 'a', 'c'); $Key = $Value }"
        $r.X -join ',' | Should -Be $Expected
    }

    It 'reads quotes inside the value' {
        (Import-Text "@{ X = @(`"it's`", 'b'); 'X[''it''''s''] :=' = 'y' }").X -join ',' | Should -Be 'y,b'
        (Import-Text "@{ X = @('say `"hi`"', 'b'); 'X[`"say `"`"hi`"`"`"] -=' = `$true }").X -join ',' | Should -Be 'b'
    }

    It 'takes an empty value, and a value with brackets' {
        @((Import-Text "@{ X = @('', 'a'); 'X[''''] -=' = `$true }").X) -join ',' | Should -Be 'a'
        (Import-Text "@{ X = @('a[1]', 'b'); 'X[''a[1]''] :=' = 'y' }").X -join ',' | Should -Be 'y,b'
    }

    It 'tells a value from an index' {
        (Import-Text "@{ X = @('1', '2', '3'); 'X[''3''] -=' = `$true }").X -join ',' | Should -Be '1,2'
        (Import-Text "@{ X = @('1', '2', '3'); 'X[1] -=' = `$true }").X -join ',' | Should -Be '1,3'
    }

    It 'only matches text with text' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{ X = @(1, 2); 'X[''1''] -=' = `$true }" }
        Get-ErrorCode { Import-Psd ./main.psd1 } $dir | Should -Contain 'PSD212'
    }

    It 'replaces with any kind of value' {
        $r = Import-Text "@{ X = @('a', 'b'); 'X[''a''] :=' = @{ N = 1 }; 'X[''b''] :=' = @(1, 2) }"
        $r.X[0].N | Should -Be 1
        $r.X[1] -join ',' | Should -Be '1,2'
    }

    It 'removing every item leaves an empty list' {
        $r = Import-Text "@{ X = @('a', 'a'); 'X[''a''] -=' = `$true }"
        $r.Contains('X') | Should -BeTrue
        @($r.X).Count | Should -Be 0
    }

    It 'runs top to bottom with the other operators' {
        $r = Import-Text "@{ X = @('a', 'b'); 'X[''a''] :=' = 'c'; 'X +=' = @('d'); 'X[''c''] -=' = `$true; 'X[0] :=' = 'e' }"
        $r.X -join ',' | Should -Be 'e,d'
    }

    It 'works on a list from a reference, and compares final values' {
        $r = Import-Text "@{ V = 'a'; Base = @('!<V>', 'b'); X = '!<Base>'; 'X[''a''] :=' = 'y' }"
        $r.X -join ',' | Should -Be 'y,b'
        $r.Base -join ',' | Should -Be 'a,b'
    }

    It 'works inside an !if, over a !merge and in Merge-Psd' {
        $text = "@{ T = 'VALUE'; X = @('a', 'b'); '!if !<T> -eq `"1`"' = @{ 'X[''a''] -=' = `$true } }"
        (Import-Text $text.Replace('VALUE', '1')).X -join ',' | Should -Be 'b'
        (Import-Text $text.Replace('VALUE', '2')).X -join ',' | Should -Be 'a,b'
        (Import-Text "@{ '!merge' = './base.psd1'; 'X[''a''] :=' = 'y' }" -More @{ 'base.psd1' = "@{ X = @('a', 'b') }" }).X -join ',' | Should -Be 'y,b'
        (Merge-Psd @{ X = @('a', 'b') }, @{ "X['a'] -=" = $true }).X -join ',' | Should -Be 'b'
    }

    It 'keeps a key without an operator as a plain key' {
        $r = Import-Text "@{ X = @('a'); 'X[''a'']' = 'p' }"
        $r.X -join ',' | Should -Be 'a'
        $r["X['a']"] | Should -Be 'p'
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

Describe 'Default operators: -Merge and Merge in the schema' {
    BeforeAll {
        $script:base = @{ Tags = @('a'); Server = @{ Ports = @(80); Host = 'h' }; Name = 'x'; Opts = @{ A = 1; B = 2 } }
    }

    It '-Merge ** makes every list add, at any depth' {
        $m = Merge-Psd $base, @{ Tags = @('b'); Server = @{ Ports = @(443) } } -Merge @{ '**' = '+=' }
        $m.Tags -join ',' | Should -Be 'a,b'
        $m.Server.Ports -join ',' | Should -Be '80,443'
        $m.Server.Host | Should -Be 'h'
    }

    It '-Merge takes key paths, * is one key, and other operators' {
        $m = Merge-Psd $base, @{ Tags = @('b', 'a'); Server = @{ Ports = @(443) } } -Merge ([ordered]@{ Tags = '|='; '*.Ports' = '=+' })
        $m.Tags -join ',' | Should -Be 'a,b'
        $m.Server.Ports -join ',' | Should -Be '443,80'
    }

    It ':= replaces a map instead of merging it' {
        $m = Merge-Psd $base, @{ Opts = @{ C = 3 } } -Merge @{ Opts = ':=' }
        @($m.Opts.Keys) -join ',' | Should -Be 'C'
    }

    It 'a key it does not match, or a value it does not fit, merges as before' {
        $m = Merge-Psd $base, @{ Tags = @('b'); Name = 'y' } -Merge @{ Server = '+=' }
        $m.Tags -join ',' | Should -Be 'b'
        (Merge-Psd $base, @{ Name = 'y' } -Merge @{ '**' = '+=' }).Name | Should -Be 'y'
    }

    It 'an operator written in the data wins' {
        $m = Merge-Psd $base, @{ 'Tags :=' = @('b') } -Merge @{ '**' = '+=' }
        $m.Tags -join ',' | Should -Be 'b'
        (Merge-Psd $base, @{ 'Tags -=' = @('a') } -Merge @{ '**' = '+=' }).Tags.Count | Should -Be 0
    }

    It 'works in an !if and in files with !merge' {
        $dir = New-TestFiles @{ 'base.psd1' = "@{ Tags = @('a') }"; 'top.psd1' = "@{ '!merge' = './base.psd1'; Tags = @('b'); '!if 1 -eq 1' = @{ Tags = @('c') } }" }
        (Import-Psd (Join-Path $dir 'top.psd1') -Merge @{ Tags = '+=' }).Tags -join ',' | Should -Be 'a,b,c'
    }

    It 'without -Merge or a schema nothing changes' {
        (Merge-Psd $base, @{ Tags = @('b') }).Tags -join ',' | Should -Be 'b'
    }

    It 'Merge in the schema, for Import-Psd, Merge-Psd and -Override' {
        $dir = New-TestFiles @{
            's.psd1'    = "@{ Properties = @{ Tags = @{ Type = 'string[]'; Merge = '+=' }; Opts = @{ Type = 'map'; Items = @{ Type = 'any'; Merge = '+=' } } } }"
            'base.psd1' = "@{ Tags = @('a'); Opts = @{ L = @(1) } }"
            'top.psd1'  = "@{ '!merge' = './base.psd1'; Tags = @('b'); Opts = @{ L = @(2) } }"
        }
        $r = Import-Psd (Join-Path $dir 'top.psd1') -Schema (Join-Path $dir 's.psd1')
        $r.Tags -join ',' | Should -Be 'a,b'
        $r.Opts.L -join ',' | Should -Be '1,2'
        (Merge-Psd (Join-Path $dir 'base.psd1'), @{ Tags = @('c') } -Schema (Join-Path $dir 's.psd1')).Tags -join ',' | Should -Be 'a,c'
        (Import-Psd (Join-Path $dir 'base.psd1') -Schema (Join-Path $dir 's.psd1') -Override @{ Tags = @('d') }).Tags -join ',' | Should -Be 'a,d'
    }

    It '-Merge wins over Merge in the schema' {
        $dir = New-TestFiles @{ 's.psd1' = "@{ Properties = @{ Tags = @{ Type = 'string[]'; Merge = '+=' } } }" }
        (Merge-Psd @{ Tags = @('a') }, @{ Tags = @('b') } -Schema (Join-Path $dir 's.psd1') -Merge @{ Tags = '=+' }).Tags -join ',' | Should -Be 'b,a'
    }

    It 'is an error for <Case>' -ForEach @(
        @{ Case = '-= in -Merge'; Code = 'PSD206'; Run = { Merge-Psd @{ A = 1 } -Merge @{ A = '-=' } } }
        @{ Case = 'an empty key path in -Merge'; Code = 'PSD206'; Run = { Merge-Psd @{ A = 1 } -Merge @{ 'A..B' = '+=' } } }
        @{ Case = 'an unknown operator in the schema'; Code = 'PSD500'; Run = { Import-Psd ./a.psd1 -Schema ./bad.psd1 } }
        @{ Case = 'a list operator on a key that is no list'; Code = 'PSD500'; Run = { Import-Psd ./a.psd1 -Schema ./notlist.psd1 } }
    ) {
        $dir = New-TestFiles @{ 'a.psd1' = '@{ A = 1 }'; 'bad.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Merge = 'x' } } }"; 'notlist.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Merge = '+=' } } }" }
        Get-ErrorCode $Run $dir | Should -Contain $Code
    }
}