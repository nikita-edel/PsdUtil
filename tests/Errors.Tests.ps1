# One case for every error code.

BeforeDiscovery {
    $deep = '@{ A = ' * 70 + '1' + ' }' * 70
    $lines = (0..30) | ForEach-Object { "    K$_ = '!<K$($_ + 1)>!<K$($_ + 1)>'" }
    $doubling = "@{`n" + ($lines -join "`n") + "`n    K31 = 'xxxxxxxxxx'`n}"
    $lines = (0..30) | ForEach-Object { "    K$_ = @('!<K$($_ + 1)>', '!<K$($_ + 1)>')" }
    $mapDoubling = "@{`n" + ($lines -join "`n") + "`n    K31 = 1`n}"

    $script:cases = @(
        # Parse
        @{ Code = 'PSD100'; Files = @{}; Run = { Import-Psd ./nope.psd1 } }
        @{ Code = 'PSD101'; Files = @{ 'main.psd1' = '@{ a = ' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD102'; Files = @{ 'main.psd1' = '@{ a = 1; A = 2 }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD103'; Files = @{ 'main.psd1' = '# only a comment' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD103'; Files = @{ 'main.psd1' = '1' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD104'; Files = @{ 'main.psd1' = "@{ a = 1 }`n@{ b = 2 }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD105'; Files = @{ 'main.psd1' = '@{ a = [int]5 }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD105'; Files = @{ 'main.psd1' = '@{ a = { 1 } }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD105'; Files = @{ 'main.psd1' = '@{ a = $env:PATH }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD105'; Files = @{ 'main.psd1' = '@{ a = $(1) }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD106'; Files = @{ 'main.psd1' = "@{ 1 = 'x' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD107'; Files = @{ 'main.psd1' = [byte[]](0x40, 0x7B, 0x61, 0x3D, 0x27, 0xC3, 0x28, 0x27, 0x7D) }; Run = { Import-Psd ./main.psd1 } }

        # Load and merge
        @{ Code = 'PSD200'; Files = @{ 'main.psd1' = "@{ '!merge' = './missing.psd1' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD201'; Files = @{ 'a.psd1' = "@{ '!merge' = './b.psd1' }"; 'b.psd1' = "@{ '!merge' = './a.psd1' }" }; Run = { Import-Psd ./a.psd1 } }
        @{ Code = 'PSD201'; Files = @{ 'a.psd1' = "@{ '!merge' = './a.psd1' }" }; Run = { Import-Psd ./a.psd1 } }
        @{ Code = 'PSD201'; Files = @{ 'a.psd1' = "@{ '!include' = './b.psd1' }"; 'b.psd1' = "@{ '!include' = './a.psd1' }" }; Run = { Import-Psd ./a.psd1 } }
        @{ Code = 'PSD202'; Files = @{ 'main.psd1' = "@{ '!merge' = './conf/*.psd1' }"; 'conf/readme.txt' = 'x' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD203'; Files = @{ 'main.psd1' = "@{ '!include' = './x/a.psd1', './y/a.psd1' }"; 'x/a.psd1' = '@{}'; 'y/a.psd1' = '@{}' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD204'; Files = @{ 'main.psd1' = "@{ '!name' = 'this' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD205'; Files = @{ 'main.psd1' = "@{ '!mrege' = './a.psd1' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD205'; Files = @{ 'main.psd1' = "@{ '!types' = './T.psm1' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD206'; Files = @{ 'main.psd1' = "@{ '!merge' = 5 }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD206'; Files = @{ 'main.psd1' = "@{ A = @{ '!merge' = './x.psd1' } }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD206'; Files = @{ 'main.psd1' = "@{ '!if true' = 1 }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD206'; Files = @{ 'main.psd1' = "@{ '!if true' = @{ '!if false' = @{} } }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD207'; Files = @{ 'main.psd1' = "@{ '!merge' = @{ Path = './a.psd1'; Keys = 'Nope' } }"; 'a.psd1' = '@{ A = 1 }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD208'; Files = @{ 'main.psd1' = "@{ '!merge' = 'https://example.com/a.psd1' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD209'; Files = @{ 'main.psd1' = "@{ 'Plugins ++' = @('x') }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD210'; Files = @{ 'main.psd1' = "@{ Server = @{ A = 1 }; 'Server +=' = @('x') }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD211'; Files = @{ 'main.psd1' = "@{ Old = 1; 'Old -=' = `$false }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD212'; Files = @{ 'main.psd1' = "@{ 'Old -=' = `$true }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD212'; Files = @{ 'main.psd1' = "@{ L = @('a'); 'L -=' = @('b') }" }; Run = { Import-Psd ./main.psd1 } }

        # References
        @{ Code = 'PSD300'; Files = @{ 'main.psd1' = "@{ A = 1; B = '!<A' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD300'; Files = @{ 'main.psd1' = "@{ A = 1; B = '!<>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD300'; Files = @{ 'main.psd1' = "@{ A = 1; B = '!<!<A>>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD300'; Files = @{ 'main.psd1' = "@{ L = @(1); B = '!<L[99999999999]>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD300'; Files = @{ 'main.psd1' = "@{ B = '!<99999999999999999999>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD301'; Files = @{ 'main.psd1' = '@{ L = @(1) }' }; Run = { Resolve-PsdReference ./main.psd1 'L[-5]' } }
        @{ Code = 'PSD301'; Files = @{ 'main.psd1' = "@{ Port = 1; B = '!<Prot>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD301'; Files = @{ 'main.psd1' = "@{ S = `$null; B = '!<S.Port>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD108'; Files = @{ 'main.psd1' = "@{ '!merge' = './s.ps1' }"; 's.ps1' = '@{ A = 1 }' }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD313'; Files = @{ 'main.psd1' = "@{ '!include' = './s.psd1'; B = '!<Db>' }"; 's.psd1' = "@{ Db = 1 }" }; Run = { Import-Psd ./main.psd1 -Include @{ run = @{ Db = 2 } } } }
        @{ Code = 'PSD302'; Files = @{ 'main.psd1' = "@{ B = '!<nope::A>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD303'; Files = @{ 'main.psd1' = "@{ A = '!<B>'; B = '!<A>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD303'; Files = @{ 'main.psd1' = "@{ A = @{ B = '!<A>' } }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD304'; Files = @{ 'main.psd1' = "@{ Name = 'x'; B = '!<Name.Sub>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD305'; Files = @{ 'main.psd1' = "@{ 'a!<b>' = 1 }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD306'; Files = @{ 'main.psd1' = "@{ M = @{ A = 1 }; T = 'x !<M>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD307'; Files = @{ 'main.psd1' = "@{ L = @(1); B = '!<L[5]>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD308'; Files = @{ 'main.psd1' = "@{ M = @{ A = 1 }; B = '!<M[0]>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD309'; Files = @{ 'main.psd1' = "@{ B = '!<@nmae>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD310'; Files = @{ 'main.psd1' = "@{ B = '!<env:PSDUTIL_TEST_NOT_SET>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD311'; Files = @{ 'main.psd1' = "@{ A = 'x'; B = '!<A | lowr>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD312'; Files = @{ 'main.psd1' = "@{ A = 'x'; B = '!<A | replace(""x"")>' }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD312'; Files = @{ 'main.psd1' = "@{ A = 5; B = '!<A | upper>' }" }; Run = { Import-Psd ./main.psd1 } }

        # Conditions
        @{ Code = 'PSD400'; Files = @{ 'main.psd1' = "@{ A = 1; '!if !<A> -eq' = @{} }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD401'; Files = @{ 'main.psd1' = "@{ A = `$true; '!if !<A>' = @{ B = 1 }; '!if !<B>' = @{ C = 1 } }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD401'; Files = @{ 'main.psd1' = "@{ A = `$true; '!if !<A>' = @{ L = @(1) }; '!if !<L[0]>' = @{ C = 1 } }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD402'; Files = @{ 'main.psd1' = "@{ M = @{ A = 1 }; '!if !<M> -gt 1' = @{} }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD403'; Files = @{ 'main.psd1' = "@{ A = 'x'; '!if !<A> -match ""(""' = @{} }" }; Run = { Import-Psd ./main.psd1 } }

        # Schema
        @{ Code = 'PSD500'; Files = @{ 'main.psd1' = '@{ A = 1 }'; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Requred = `$true } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD501'; Files = @{ 'main.psd1' = "@{ A = 'x' }"; 's.psd1' = "@{ Properties = @{ A = 'int' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD502'; Files = @{ 'main.psd1' = '@{ A = 1 }'; 's.psd1' = "@{ Properties = @{ A = 'int'; B = @{ Type = 'int'; Required = `$true } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD503'; Files = @{ 'main.psd1' = '@{ Plugns = 1 }'; 's.psd1' = "@{ Properties = @{ Plugins = 'int' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD504'; Files = @{ 'main.psd1' = "@{ A = 'Loud' }"; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'string'; Enum = 'Debug', 'Info' } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD505'; Files = @{ 'main.psd1' = "@{ A = 'ABC' }"; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'string'; Pattern = '^[a-z]+$' } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD506'; Files = @{ 'main.psd1' = '@{ A = 70000 }'; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Min = 1; Max = 65535 } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD507'; Files = @{ 'main.psd1' = "@{ A = 'x' }"; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'string'; Pattern = '(' } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD508'; Files = @{ 'main.psd1' = '@{ A = 1 }'; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Default = 'x' } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD509'; Files = @{ 'main.psd1' = '@{ A = 1 }'; 's.psd1' = "@{ Properties = @{ A = 'integer' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD510'; Files = @{ 'main.psd1' = '@{ A = 1 }'; 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Min = 5; Max = 1 } } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD511'; Files = @{ 'main.psd1' = "@{ '!schema' = './missing.schema.psd1'; A = 1 }" }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD512'; Files = @{ 's.psd1' = "@{ Properties = @{ A = 'int' } }" }; Run = { New-PsdType -Schema ./s.psd1 -Name '1bad' } }
        @{ Code = 'PSD513'; Files = @{ 'main.psd1' = "@{ A = 'x' }"; 's.psd1' = "@{ Properties = @{ A = '[NoSuchEnum]' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD514'; Files = @{ 'main.psd1' = "@{ A = 'x' }"; 's.psd1' = "@{ '!types' = './missing.psm1'; Properties = @{ A = 'string' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }
        @{ Code = 'PSD515'; Files = @{ 'main.psd1' = "@{ A = 'x' }"; 'a.psm1' = 'enum E { X }'; 'b.psm1' = 'enum E { Y }'; 's.psd1' = "@{ '!types' = './a.psm1', './b.psm1'; Properties = @{ A = 'string' } }" }; Run = { Import-Psd ./main.psd1 -Schema ./s.psd1 } }

        # Output
        @{ Code = 'PSD600'; Files = @{}; Run = { $h = @{}; $h.Self = $h; ConvertTo-Psd $h } }
        @{ Code = 'PSD601'; Files = @{}; Run = { ConvertTo-Psd @{ A = @{ B = @{ C = 1 } } } -Depth 2 } }
        @{ Code = 'PSD602'; Files = @{}; Run = { ConvertTo-Psd @{ A = { 1 } } } }
        @{ Code = 'PSD603'; Files = @{}; Run = { ConvertTo-Psd @{ 'A +=' = 1 } } }
        @{ Code = 'PSD604'; Files = @{}; Run = { ConvertTo-Psd @{ A = 1 } -Format @{ Indnet = 2 } } }
        @{ Code = 'PSD605'; Files = @{}; Run = { Export-Psd @{ A = 1 } -Path ./no/such/folder/out.psd1 } }
        @{ Code = 'PSD606'; Files = @{ 'main.psd1' = '@{ A = ' }; Run = { Update-Psd ./main.psd1 -Key A -Value 1 } }
        @{ Code = 'PSD606'; Files = @{ 'main.psd1' = [byte[]](0x40, 0x7B, 0x61, 0x3D, 0x27, 0xC3, 0x28, 0x27, 0x7D) }; Run = { Format-Psd ./main.psd1 } }
        @{ Code = 'PSD607'; Files = @{ 'main.psd1' = "@{ A = 'x' }" }; Run = { Update-Psd ./main.psd1 -Key 'A.B' -Value 1 } }

        # Limits
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = $deep }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = $doubling }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = $mapDoubling }; Run = { Import-Psd ./main.psd1 } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = "@{ A = '!<B>'; B = '!<C>'; C = '!<D>'; D = 1 }" }; Run = { Import-Psd ./main.psd1 -Limits @{ MaxDepth = 2 } } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = "@{ '!merge' = './a.psd1' }"; 'a.psd1' = '@{}' }; Run = { Import-Psd ./main.psd1 -Limits @{ MaxFiles = 1 } } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = "@{ A = 'xxxxxxxxxxxxxxxxxxxx' }" }; Run = { Import-Psd ./main.psd1 -Limits @{ MaxFileSize = 10 } } }
        @{ Code = 'PSD700'; Files = @{ 'main.psd1' = "@{ A = '$('a' * 30)b'; '!if !<A> -match ""^(a+)+$""' = @{} }" }; Run = { Import-Psd ./main.psd1 -Limits @{ RegexTimeout = 0.2 } } }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $env:PSDUTIL_TEST_NOT_SET = $null
}

Describe 'Error codes' {
    It '<Code> is reported' -ForEach $cases {
        $dir = New-TestFiles $Files
        $codes = @(Get-ErrorCode $Run $dir)
        $codes | Should -Contain $Code
    }
}

Describe 'Error messages' {
    It 'point to the file, line and the part that is wrong, with a hint' {
        $dir = New-TestFiles @{ 'base.psd1' = "@{`n    Server = @{ Port = 8080 }`n}"; 'main.psd1' = "@{`n    '!merge' = './base.psd1'`n    BasePort = '!<base::Server.Prot>'`n}" }
        Push-Location $dir
        try { $e = @(Import-Psd ./main.psd1 2>&1 3>$null | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) }
        finally { Pop-Location }
        $e.Count | Should -Be 1
        $m = $e[0].Exception.Message
        $m | Should -Match "main\.psd1, line 3: 'Prot' doesn't exist under Server in base\.psd1\."
        $m | Should -Match "BasePort = '!<base::Server.Prot>'"
        $m | Should -Match "\^\^\^\^"
        $m | Should -Match "Did you mean 'Port'\?"
        $m | Should -Match '\[PSD301\]'
        $e[0].TargetObject.Line | Should -Be 3
        $e[0].TargetObject.Code | Should -Be 'PSD301'
    }

    It 'are all collected, not just the first' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{ A = '!<X>'; B = '!<Y>'; C = '!<Z>' }" }
        @(Get-ErrorCode { Import-Psd ./main.psd1 } $dir).Count | Should -Be 3
    }

    It 'show the whole cycle' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{`n    A = '!<B>'`n    B = '!<C>'`n    C = '!<A>'`n}" }
        Push-Location $dir
        try { $e = @(Import-Psd ./main.psd1 2>&1 3>$null | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) }
        finally { Pop-Location }
        $e.Count | Should -Be 1
        $e[0].Exception.Message | Should -Match '(?s)A .*B .*C .*back to A'
    }

    It 'stop at the first one with -ErrorAction Stop' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{ A = '!<X>'; B = '!<Y>' }" }
        Push-Location $dir
        try { { Import-Psd ./main.psd1 -ErrorAction Stop } | Should -Throw -ErrorId 'PSD301*' }
        finally { Pop-Location }
    }
}
