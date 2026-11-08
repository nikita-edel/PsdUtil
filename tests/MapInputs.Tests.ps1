#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# -Include, '!name' in maps, -Schema on Merge-Psd, and generated classes that keep their map.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/PsdUtil/PsdUtil.psd1') -Force
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    function Get-ErrorText {
        param([scriptblock] $Script, [string] $Dir)
        Push-Location $Dir
        try { $records = @(& $Script 2>&1 3>$null) }
        finally { Pop-Location }
        foreach ($r in $records) {
            if ($r -is [System.Management.Automation.ErrorRecord]) { $r.Exception.Message }
        }
    }
}

Describe '-Include' {
    BeforeAll {
        $script:run = @{ run = @{ Stage = 'prod'; Root = 'C:\app' } }
        $script:app = "@{ Log = '!<run::Root>\log'; '!if !<run::Stage> -eq `"prod`"' = @{ Replicas = 3 } }"
    }

    It 'Import-Psd reads the map through its name, also in conditions' {
        $dir = New-TestFiles @{ 'app.psd1' = $app }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include $run
        $r.Log | Should -Be 'C:\app\log'
        $r.Replicas | Should -Be 3
    }

    It 'ConvertFrom-Psd takes it too' {
        (ConvertFrom-Psd -Text $app -Include $run).Log | Should -Be 'C:\app\log'
    }

    It 'Merge-Psd takes it too' {
        $m = Merge-Psd @{ A = 1 }, @{ Log = '!<run::Root>' } -Include $run
        $m.Log | Should -Be 'C:\app'
    }

    It 'is readable from every file in the merge chain' {
        $dir = New-TestFiles @{ 'base.psd1' = "@{ B = '!<run::Stage>' }"; 'app.psd1' = "@{ '!merge' = './base.psd1' }" }
        (Import-Psd (Join-Path $dir 'app.psd1') -Include $run).B | Should -Be 'prod'
    }

    It 'keeps its keys out of the result' {
        $dir = New-TestFiles @{ 'app.psd1' = $app }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include $run
        @($r.Keys | Sort-Object) -join ',' | Should -Be 'Log,Replicas'
    }

    It 'is not checked by the schema' {
        $dir = New-TestFiles @{ 'app.psd1' = $app; 's.psd1' = "@{ Properties = @{ Log = 'string'; Replicas = 'int' } }" }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include $run -Schema (Join-Path $dir 's.psd1')
        $r.Replicas | Should -Be 3
    }

    It 'works like an included file: references and @name inside the map' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ V = '!<run::Url>'; N = '!<run::Who>' }" }
        $inc = @{ run = @{ Host = 'h'; Url = 'http://!<Host>'; Who = '!<@name>' } }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include $inc
        $r.V | Should -Be 'http://h'
        $r.N | Should -Be 'run'
    }

    It 'does not allow the name this' {
        $dir = New-TestFiles @{ 'app.psd1' = '@{ A = 1 }' }
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ this = @{ A = 1 } } } $dir | Should -Contain 'PSD204'
    }

    It 'gives PSD203 for a name used by <Case>' -ForEach @(
        @{ Case = 'the file itself'; Entry = 'run.psd1'; Files = @{ 'run.psd1' = '@{ A = 1 }' } }
        @{ Case = 'a merged file'; Entry = 'app.psd1'; Files = @{ 'app.psd1' = "@{ '!merge' = './run.psd1' }"; 'run.psd1' = '@{ A = 1 }' } }
        @{ Case = 'an included file'; Entry = 'app.psd1'; Files = @{ 'app.psd1' = "@{ '!include' = './run.psd1' }"; 'run.psd1' = '@{ A = 1 }' } }
    ) {
        $dir = New-TestFiles $Files
        $entryFile = $Entry
        Get-ErrorCode { Import-Psd "./$entryFile" -Include @{ run = @{ A = 1 } } } $dir | Should -Contain 'PSD203'
    }

    It 'gives PSD301 with a suggestion for a missing key' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ A = '!<run::Stgae>' }" }
        $t = Get-ErrorText { Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'x' } } } $dir
        "$t" | Should -Match 'PSD301'
        "$t" | Should -Match "Did you mean 'Stage'"
    }

    It 'gives PSD206 for a value that is not a map, or a bad name' {
        $dir = New-TestFiles @{ 'app.psd1' = '@{ A = 1 }' }
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ run = 5 } } $dir | Should -Contain 'PSD206'
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ 'a b' = @{} } } $dir | Should -Contain 'PSD206'
    }

    It 'reports problems in parts nothing reads, like an included file' {
        $dir = New-TestFiles @{ 'app.psd1' = '@{ A = 1 }' }
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ run = @{ B = '!<Nope>' } } } $dir | Should -Contain 'PSD301'
    }

    It 'can not be read from inside an included file' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ '!include' = './s.psd1'; A = '!<s::B>' }"; 's.psd1' = "@{ B = '!<run::Stage>' }" }
        Get-ErrorCode { Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'x' } } } $dir | Should -Contain 'PSD302'
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

    It 'has a constructor with no arguments and one that takes a map' {
        (Invoke-Typed '[App]::new()').GetType().Name | Should -Be 'App'
        (Invoke-Typed "[App]::new(@{ Name = 'x' })").Name | Should -Be 'x'
    }

    It 'keeps the map unchanged in a hidden property' {
        $inst = Invoke-Typed $goal
        $inst.__PsdMap.Count | Should -Be 5
        $inst.__PsdMap['Url'] | Should -BeExactly 'http://!<Host>'
        (Get-Member -InputObject $inst -Name __PsdMap) | Should -BeNullOrEmpty
    }

    It 'still sets the properties' {
        (Invoke-Typed $goal).Name | Should -Be 'billing'
    }

    It 'still throws for <Case>' -ForEach @(
        @{ Case = 'a typo'; Body = "[App]@{ Nmae = 'x' }"; Match = '*Nmae*' }
        @{ Case = 'a typo in a nested map'; Body = '[App]@{ Server = @{ Nope = 1 } }'; Match = '*Nope*' }
        @{ Case = 'a typo with a reference'; Body = "[App]@{ Nmae = '!<X>' }"; Match = '*Nmae*' }
        @{ Case = 'something close to an operator'; Body = "[App]@{ 'Plugins ++' = @('x') }"; Match = '*Plugins ++*' }
        @{ Case = 'a wrong type'; Body = "[App]@{ Replicas = 'abc' }"; Match = '*Replicas*' }
    ) {
        $text = $Body
        { Invoke-Typed $text } | Should -Throw $Match
    }

    It 'allows a reference in a typed property' {
        $inst = Invoke-Typed "[App]@{ Replicas = '!<N>' }"
        $inst.Replicas | Should -BeNullOrEmpty
        ConvertTo-Psd $inst | Should -Match "Replicas = '!<N>'"
    }

    It 'ConvertTo-Psd writes what was written' {
        $t = ConvertTo-Psd (Invoke-Typed $goal)
        $t | Should -Match "Url = 'http://!<Host>'"
        $t | Should -Not -Match '!!<'
        $t | Should -Match "'Plugins \+=' = @\('cache'\)"
        $t | Should -Match "'!if !<Stage> -eq ""prod""' = @\{"
    }

    It 'leaves unset properties out' {
        $t = ConvertTo-Psd (Invoke-Typed $goal)
        $t | Should -Not -Match 'Server'
        $t | Should -Not -Match '__PsdMap'
        $t | Should -Not -Match '\$null'
    }

    It 'Export-Psd writes a file that loads like a data file' {
        $file = Join-Path $TestDrive 'typed.psd1'
        Export-Psd -InputObject (Invoke-Typed $goal) -Path $file
        $r = Import-Psd $file -Override @{ Stage = 'prod' }
        $r.Url | Should -Be 'http://h'
        $r.Plugins -join ',' | Should -Be 'cache'
        $r.Replicas | Should -Be 3
    }

    It 'Merge-Psd uses the kept map' {
        $inst = Invoke-Typed $goal
        $r = Merge-Psd @{ Plugins = @('a'); Stage = 'prod' }, $inst
        $r.Plugins -join ',' | Should -Be 'a,cache'
        $r.Replicas | Should -Be 3
        $r.Url | Should -Be 'http://h'
    }

    It '-Override uses the kept map' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ Plugins = @('a'); Stage = 'prod' }" }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Override (Invoke-Typed $goal)
        $r.Plugins -join ',' | Should -Be 'a,cache'
        $r.Replicas | Should -Be 3
    }

    It 'nested classes keep their map when <Case>' -ForEach @(
        @{ Case = 'cast'; Body = "[App]@{ Server = [AppServer]@{ Host = '!<X>'; 'Tags +=' = @('a'); '!if !<X>' = @{ Port = 1 } } }" }
        @{ Case = 'given as a plain map'; Body = "[App]@{ Server = @{ Host = '!<X>'; 'Tags +=' = @('a'); '!if !<X>' = @{ Port = 1 } } }" }
    ) {
        $inst = Invoke-Typed $Body
        $inst.Server.GetType().Name | Should -Be 'AppServer'
        $t = ConvertTo-Psd $inst
        $t | Should -Match "Host = '!<X>'"
        $t | Should -Not -Match '!!<'
        $t | Should -Match "'Tags \+=' = @\('a'\)"
        $t | Should -Match "'!if !<X>' = @\{"
        $t | Should -Not -Match 'Port = \$null'
    }

    It 'nested classes work through Merge-Psd' {
        $inst = Invoke-Typed "[App]@{ Server = [AppServer]@{ 'Tags +=' = @('b') } }"
        (Merge-Psd @{ Server = @{ Tags = @('a'); Port = 1 } }, $inst).Server.Tags -join ',' | Should -Be 'a,b'
    }

    It 'lists of nested classes keep their map' {
        $t = ConvertTo-Psd (Invoke-Typed "[App]@{ Backups = @(@{ Host = '!<X>'; 'y +=' = 1 }) }")
        $t | Should -Match "Host = '!<X>'"
        $t | Should -Match "'y \+=' = 1"
    }

    Context 'made with new()' {
        BeforeAll { $script:plain = Invoke-Typed "`$c = [App]::new(); `$c.Name = 'a'; `$c.Url = '!<X>'; `$c" }

        It 'has no kept map' { $plain.__PsdMap | Should -BeNullOrEmpty }

        It 'is written from its properties, as before' {
            $t = ConvertTo-Psd $plain
            $t | Should -Match "Name = 'a'"
            $t | Should -Match "Url = '!!<X>'"
            $t | Should -Not -Match 'Replicas'
            $t | Should -Not -Match '__PsdMap'
        }

        It 'is still not accepted by Merge-Psd or -Override' {
            $dir = New-TestFiles @{ 'app.psd1' = '@{ A = 1 }' }
            $inst = $plain
            Get-ErrorCode { Merge-Psd @($inst) } $dir | Should -Contain 'PSD206'
            Get-ErrorCode { Import-Psd ./app.psd1 -Override $inst } $dir | Should -Contain 'PSD206'
        }
    }

    It 'stays out of autocomplete' {
        $src = "using module '$mod'`n`$psdTyped = [App]::new(); `$psdTyped."
        $names = (TabExpansion2 -inputScript $src -cursorColumn $src.Length).CompletionMatches.CompletionText
        $names | Should -Contain 'Name'
        $names | Should -Not -Contain '__PsdMap'
        $names | Should -Not -Contain 'Apply('
    }
}
