BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Generated types' {
    It 'matches examples/typed/App.Types.psm1' {
        Push-Location (Join-Path $Examples 'typed')
        try { $gen = New-PsdType -Schema ../config/app.schema.psd1 -Name App }
        finally { Pop-Location }
        $expected = [IO.File]::ReadAllText((Join-Path $Examples 'typed/App.Types.psm1')).Replace("`r`n", "`n")
        $gen.Replace(' -Name App', ' -Path ./App.Types.psm1 -Name App') | Should -BeExactly $expected
    }

    It 'gives classes that run and complete' {
        Push-Location (Join-Path $Examples 'typed')
        try {
            $o = & ./app.config.ps1
            $mod = (Resolve-Path ./App.Types.psm1).Path
            $src = "using module $mod`n`$s = [AppServer]::new(); `$s."
            $r = TabExpansion2 -inputScript $src -cursorColumn $src.Length
        }
        finally { Pop-Location }
        $o.Server.Port | Should -Be 9000
        $o.Logging.Level | Should -Be 'Warn'
        $r.CompletionMatches.CompletionText | Should -Contain 'Host'
    }
}

Describe 'Classes of named values from -Constant' {
    BeforeAll {
        $script:constDir = New-TestFiles @{ 's.psd1' = "@{ Properties = @{ Region = 'string'; Size = @{ Type = 'string'; Enum = 'S', 'M' } } }" }
        $script:constGen = {
            param($Constant)
            Push-Location $constDir
            try { New-PsdType -Schema ./s.psd1 -Name App -Constant $Constant }
            finally { Pop-Location }
        }
    }

    It 'types each value and writes it as ConvertTo-Psd does, exactly as given' {
        $t = & $constGen ([ordered]@{ Port = [ordered]@{ Http = 80; Big = 5000000000; On = $true; Ratio = 0.5; None = $null; Ref = '!<A>'; Tags = @('a', 'b'); Limits = [ordered]@{ Cpu = 8 } } })
        $t | Should -Match "static \[int\] \`$Http = 80"
        $t | Should -Match "static \[long\] \`$Big = 5000000000"
        $t | Should -Match "static \[bool\] \`$On = \`$true"
        $t | Should -Match "static \[double\] \`$Ratio = 0\.5"
        $t | Should -Match "static \[object\] \`$None = \`$null"
        $t | Should -Match "static \[string\] \`$Ref = '!<A>'"
        $t | Should -Match "static \[object\[\]\] \`$Tags = @\('a', 'b'\)"
        $t | Should -Match "static \[hashtable\] \`$Limits = @\{"
    }

    It 'gives the values back, typed' {
        $mod = Join-Path $constDir 'Values.Types.psm1'
        Push-Location $constDir
        try { New-PsdType -Schema ./s.psd1 -Path $mod -Name App -Constant @{ Port = @{ Http = 80; Tags = @('a', 'b'); Limits = @{ Cpu = 8 } }; Flag = @($true, 3) } }
        finally { Pop-Location }
        $r = & ([scriptblock]::Create("using module '$mod'`n[Port]::Http; [Port]::Limits.Cpu; [Port]::Tags.Count; [Flag]::_True; [Flag]::_3"))
        $r[0] | Should -BeOfType [int]
        $r[0] | Should -Be 80
        $r[1] | Should -Be 8
        $r[2] | Should -Be 2
        $r[3] | Should -BeExactly $true
        $r[4] | Should -Be 3
    }

    It 'writes one static string per value, names made valid' {
        $t = & $constGen ([ordered]@{ Region = @('eu-west', 'us-east', '1st', "it's") })
        $t | Should -Match "class Region \{"
        $t | Should -Match "static \[string\] \`$eu_west = 'eu-west'"
        $t | Should -Match "static \[string\] \`$_1st = '1st'"
        $t | Should -Match "static \[string\] \`$it_s = 'it''s'"
        $t | Should -Match '-Constant @\{ Region \}'
    }

    It 'gives classes that run and complete' {
        $mod = Join-Path $constDir 'Const.Types.psm1'
        Push-Location $constDir
        try { New-PsdType -Schema ./s.psd1 -Path $mod -Name App -Constant @{ Region = @('eu-west') } }
        finally { Pop-Location }
        (& ([scriptblock]::Create("using module '$mod'`n[Region]::eu_west"))) | Should -BeExactly 'eu-west'
        $src = "using module '$mod'`n[Region]::"
        (TabExpansion2 -inputScript $src -cursorColumn $src.Length).CompletionMatches.CompletionText | Should -Contain 'eu_west'
    }

    It 'writes an empty class for an empty list' {
        & $constGen @{ Empty = @() } | Should -Match "class Empty \{\s*\}"
    }

    It 'is an error for <Case>' -ForEach @(
        @{ Case = 'two values with one name'; Constant = @{ Region = @('eu-west', 'eu_west') } }
        @{ Case = 'a value without a letter or digit'; Constant = @{ Region = @('--') } }
        @{ Case = 'a class name that is no name'; Constant = @{ '1bad' = @('x') } }
        @{ Case = 'the name of the top class'; Constant = @{ App = @('x') } }
        @{ Case = 'the name of a class of the schema'; Constant = @{ AppSize = @('x') } }
        @{ Case = 'a map in a list, which has no name'; Constant = @{ Region = @(@{ A = 1 }) } }
        @{ Case = 'two names of a map that become one'; Constant = @{ Port = [ordered]@{ 'a-b' = 1; 'a_b' = 2 } } }
    ) {
        $c = $Constant
        Get-ErrorCode { New-PsdType -Schema ./s.psd1 -Name App -Constant $c } $constDir | Should -Contain 'PSD512'
    }

    It 'leaves the schema check alone' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ Region = 'anything' }"; 's.psd1' = "@{ Properties = @{ Region = 'string' } }" }
        (Import-Psd (Join-Path $dir 'app.psd1') -Schema (Join-Path $dir 's.psd1')).Region | Should -Be 'anything'
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
