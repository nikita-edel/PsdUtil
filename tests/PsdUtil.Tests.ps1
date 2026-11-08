#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../src/PsdUtil/PsdUtil.psd1') -Force
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $script:Examples = Join-Path $PSScriptRoot '../plan/examples'
    $env:APP_STAGE = $null

    function Import-Text {
        param([string] $Text, [hashtable] $More = @{}, [hashtable] $Params = @{})
        $files = @{ 'main.psd1' = $Text }
        foreach ($k in $More.Keys) { $files[$k] = $More[$k] }
        $dir = New-TestFiles $files
        Import-Psd (Join-Path $dir 'main.psd1') @Params
    }

    function Get-ExpectedResult {
        param([string] $Folder)
        $dir = [IO.Path]::GetFullPath((Join-Path $Examples $Folder))
        $text = [IO.File]::ReadAllText((Join-Path $dir 'result.psd1')).Replace('C:/app/config', $dir.Replace('\', '/'))
        $file = Join-Path $TestDrive "expected-$Folder.psd1"
        [IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $true))
        $expected = Import-PowerShellDataFile $file
        $os = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        if ($expected.Contains('Builtins')) {
            $expected.Builtins.Os = $os
            if ($os -ne 'windows') { $expected.Checks.Remove('Os') }
        }
        $expected
    }
}

Describe 'The examples' {
    It 'config/last.psd1 gives config/result.psd1' {
        $got = Import-Psd (Join-Path $Examples 'config/last.psd1')
        Compare-TestValue (Get-ExpectedResult 'config') $got | Should -BeNullOrEmpty
    }

    It 'everything/app.psd1 gives everything/result.psd1' {
        $got = Import-Psd (Join-Path $Examples 'everything/app.psd1')
        Compare-TestValue (Get-ExpectedResult 'everything') $got | Should -BeNullOrEmpty
    }

    It 'every example .psd1 still loads with Import-PowerShellDataFile' {
        foreach ($f in Get-ChildItem $Examples -Recurse -Filter *.psd1) {
            { Import-PowerShellDataFile $f.FullName } | Should -Not -Throw -Because $f.Name
        }
    }

    It 'prod turns on the !if in base, and next.psd1 still wins' {
        $p = Import-Psd (Join-Path $Examples 'config/last.psd1') -Override @{ Stage = 'prod' }
        $p.Server.Tls.Enabled | Should -BeTrue
        $p.Server.Port | Should -Be 9000
        $p.Plugins -join ',' | Should -Be 'core,auth,metrics,cache'
    }
}

Describe 'Filters' {
    BeforeAll {
        $r = Import-Text @"
@{
    A = '  Hello World  '
    L = @('c', 'a', 'c', 'b')
    M = @{ A = 1; B = 2 }
    Lower   = '!<A | lower>'
    Upper   = '!<A | upper>'
    Trim    = '!<A | trim>'
    Replace = '!<A | replace("World", "There")>'
    Split   = '!<A | trim | split(" ")>'
    Join    = '!<L | join("-")>'
    First   = '!<L | first>'
    Last    = '!<L | last>'
    Sort    = '!<L | sort>'
    Unique  = '!<L | unique>'
    Count   = '!<L | count>'
    Keys    = '!<M | keys>'
    Values  = '!<M | values>'
    Null    = '!<?Missing | upper>'
    Empty   = @()
    NoFirst = '!<Empty | first>'
    Slug    = '!<A | trim | lower | replace(" ", "-")>'
}
"@
    }
    It 'lower' { $r.Lower | Should -BeExactly '  hello world  ' }
    It 'upper' { $r.Upper | Should -BeExactly '  HELLO WORLD  ' }
    It 'trim' { $r.Trim | Should -BeExactly 'Hello World' }
    It 'replace' { $r.Replace | Should -BeExactly '  Hello There  ' }
    It 'split' { $r.Split -join '|' | Should -Be 'Hello|World' }
    It 'join' { $r.Join | Should -Be 'c-a-c-b' }
    It 'first and last' { $r.First | Should -Be 'c'; $r.Last | Should -Be 'b' }
    It 'sort' { $r.Sort -join ',' | Should -Be 'a,b,c,c' }
    It 'unique keeps the first of each, in order' { $r.Unique -join ',' | Should -Be 'c,a,b' }
    It 'count' { $r.Count | Should -Be 4 }
    It 'keys and values' { $r.Keys -join ',' | Should -Be 'A,B'; $r.Values -join ',' | Should -Be '1,2' }
    It 'pass $null through' { $r.Null | Should -BeNullOrEmpty; $r.Contains('Null') | Should -BeTrue }
    It 'first on an empty list is $null' { $r.NoFirst | Should -BeNullOrEmpty }
    It 'chain' { $r.Slug | Should -Be 'hello-world' }
}

Describe 'References' {
    It 'keep the type when they are the whole value' {
        $r = Import-Text "@{ N = 5; D = 1.5; B = `$true; L = @(1, 2); M = @{ X = 1 }; RN = '!<N>'; RD = '!<D>'; RB = '!<B>'; RL = '!<L>'; RM = '!<M>' }"
        $r.RN | Should -BeOfType [int]
        $r.RD | Should -BeOfType [double]
        $r.RB | Should -BeOfType [bool]
        , $r.RL | Should -BeOfType [object[]]
        $r.RM | Should -BeOfType [System.Collections.IDictionary]
    }

    It 'turn into text inside other text, with $null as empty' {
        $r = Import-Text "@{ N = 5; D = 1.5; Z = `$null; T = 'n=!<N> d=!<D> z=[!<Z>]' }"
        $r.T | Should -BeExactly 'n=5 d=1.5 z=[]'
    }

    It 'resolve through other references and late, after merging' {
        $r = Import-Text "@{ '!merge' = './base.psd1'; Host = 'final' }" @{ 'base.psd1' = "@{ Host = 'base'; Url = 'http://!<Host>'; Again = '!<Url>' }" }
        $r.Url | Should -Be 'http://final'
        $r.Again | Should -Be 'http://final'
    }

    It 'support indexes, negative indexes and quoted keys' {
        $r = Import-Text "@{ L = @('a', 'b', 'c'); 'my.key' = @{ 'with space' = 1 }; 'say`"hi' = 2; '!!bang' = 3; A = '!<L[0]>'; B = '!<L[-1]>'; C = '!<`"my.key`".`"with space`">'; D = '!<`"say`"`"hi`">'; E = '!<`"!bang`">' }"
        $r.A | Should -Be 'a'
        $r.B | Should -Be 'c'
        $r.C | Should -Be 1
        $r.D | Should -Be 2
        $r.E | Should -Be 3
        $r.Contains('!bang') | Should -BeTrue
    }

    It 'fall back on missing or $null, in a chain' {
        $r = Import-Text "@{ Z = `$null; A = '!<Missing ?? `"x`">'; B = '!<Z ?? 5>'; C = '!<M1 ?? M2 ?? true>'; D = '!<?Missing>'; E = '!<M ?? null>' }"
        $r.A | Should -Be 'x'
        $r.B | Should -Be 5
        $r.C | Should -BeTrue
        $r.D | Should -BeNullOrEmpty
        $r.E | Should -BeNullOrEmpty
    }

    It 'read environment variables' {
        $env:PSDUTIL_TEST_VALUE = 'from env'
        try { (Import-Text "@{ A = '!<env:PSDUTIL_TEST_VALUE>'; B = '!<env:PSDUTIL_NOPE ?? `"def`">' }") | ForEach-Object { $_.A + '|' + $_.B } | Should -Be 'from env|def' }
        finally { $env:PSDUTIL_TEST_VALUE = $null }
    }

    It 'have built-ins for the last file and for this file' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{ '!merge' = './base.psd1' }"; 'base.psd1' = "@{ Name = '!<@name>'; Own = '!<this::@name>'; Dir = '!<@dir>'; File = '!<this::@file>' }" }
        $r = Import-Psd (Join-Path $dir 'main.psd1')
        $r.Name | Should -Be 'main'
        $r.Own | Should -Be 'base'
        $r.Dir | Should -Be ($dir.Replace('\', '/'))
        $r.File | Should -Be ((Join-Path $dir 'base.psd1').Replace('\', '/'))
    }

    It 'keep !!< as a literal !<' {
        (Import-Text "@{ A = 'x !!<B> y' }").A | Should -BeExactly 'x !<B> y'
    }

    It 'copy maps, so nothing is shared in the result' {
        $r = Import-Text "@{ M = @{ X = 1 }; A = '!<M>'; B = '!<M>' }"
        $r.A.X = 99
        $r.B.X | Should -Be 1
        $r.M.X | Should -Be 1
    }

    It 'can warn, null or keep instead of failing' {
        $dir = New-TestFiles @{ 'main.psd1' = "@{ A = '!<Nope>' }" }
        $w = $null
        $r = Import-Psd (Join-Path $dir 'main.psd1') -UnresolvedReference Warn -WarningVariable w -WarningAction SilentlyContinue
        $r.A | Should -BeNullOrEmpty
        $w.Count | Should -Be 1
        "$($w[0])" | Should -Match "'Nope' doesn't exist"
        (Import-Text "@{ A = '!<Nope>' }" -Params @{ UnresolvedReference = 'Null' }).A | Should -BeNullOrEmpty
        (Import-Text "@{ A = 'x !<Nope> y' }" -Params @{ UnresolvedReference = 'Keep' }).A | Should -BeExactly 'x !<Nope> y'
    }

    It 'keep numbers as their type' {
        $r = Import-Text "@{ A = 1kb; B = 0x10; C = -1; D = '!<A>' }"
        $r.D | Should -BeOfType [int]
        $r.D | Should -Be 1024
        $r.B | Should -Be 16
    }
}

Describe 'Merging' {
    It 'deep merges maps and replaces lists' {
        $r = Import-Text "@{ '!merge' = './base.psd1'; S = @{ B = 2 }; L = @('x') }" @{ 'base.psd1' = "@{ S = @{ A = 1 }; L = @('a', 'b') }" }
        $r.S.A | Should -Be 1
        $r.S.B | Should -Be 2
        $r.L -join ',' | Should -Be 'x'
    }

    It 'has all the operators' {
        $r = Import-Text @"
@{
    '!merge' = './base.psd1'
    'P +=' = @('end')
    'Q =+' = @('start')
    'U |=' = @('a', 'new')
    'R -=' = @('b')
    'O -=' = @('Old')
    'Gone -=' = `$true
    'Legacy :=' = @{ C = 3 }
    'New +=' = @('x')
}
"@ @{ 'base.psd1' = "@{ P = @('a'); Q = @('a'); U = @('a'); R = @('a', 'b'); O = @{ Keep = 1; Old = 2 }; Gone = 1; Legacy = @{ A = 1 } }" }
        $r.P -join ',' | Should -Be 'a,end'
        $r.Q -join ',' | Should -Be 'start,a'
        $r.U -join ',' | Should -Be 'a,new'
        $r.R -join ',' | Should -Be 'a'
        @($r.O.Keys) -join ',' | Should -Be 'Keep'
        $r.Contains('Gone') | Should -BeFalse
        @($r.Legacy.Keys) -join ',' | Should -Be 'C'
        $r.New -join ',' | Should -Be 'x'
    }

    It 'runs plain keys first, then operators, in the same file' {
        (Import-Text "@{ 'H +=' = @('b'); H = @('a') }").H -join ',' | Should -Be 'a,b'
    }

    It 'compares final values in |= and -=' {
        $r = Import-Text "@{ '!merge' = './base.psd1'; 'N |=' = @('!<this::@name>') }" @{ 'base.psd1' = "@{ N = @('!<this::@name>') }" }
        $r.N -join ',' | Should -Be 'base,main'
    }

    It 'sets $null without deleting, and a later map does not bring old keys back' {
        $dir = New-TestFiles @{ 'a.psd1' = '@{ S = @{ A = 1; B = 2 } }'; 'b.psd1' = "@{ '!merge' = './a.psd1'; S = `$null }"; 'c.psd1' = "@{ '!merge' = './b.psd1'; S = @{ C = 3 } }" }
        $b = Import-Psd (Join-Path $dir 'b.psd1')
        $b.Contains('S') | Should -BeTrue
        $b.S | Should -BeNullOrEmpty
        @((Import-Psd (Join-Path $dir 'c.psd1')).S.Keys) -join ',' | Should -Be 'C'
    }

    It 'lets a key change type' {
        (Import-Text "@{ '!merge' = './base.psd1'; F = @{ X = 1 } }" @{ 'base.psd1' = "@{ F = 'text' }" }).F.X | Should -Be 1
    }

    It 'merges only some keys with Keys' {
        $r = Import-Text "@{ '!merge' = @{ Path = './a.psd1'; Keys = 'Logging' } }" @{ 'a.psd1' = "@{ Logging = @{ Level = 'Info' }; Ignored = 1 }" }
        $r.Logging.Level | Should -Be 'Info'
        $r.Contains('Ignored') | Should -BeFalse
    }

    It 'applies globs in alphabetical order' {
        $r = Import-Text "@{ '!merge' = './conf/*.psd1' }" @{ 'conf/20-b.psd1' = "@{ V = 'b'; 'L +=' = @('b') }"; 'conf/10-a.psd1' = "@{ V = 'a'; 'L +=' = @('a') }" }
        $r.V | Should -Be 'b'
        $r.L -join ',' | Should -Be 'a,b'
    }

    It 'loads a file reached twice once' {
        $r = Import-Text "@{ '!merge' = './b.psd1', './c.psd1' }" @{ 'a.psd1' = "@{ 'L +=' = @('a') }"; 'b.psd1' = "@{ '!merge' = './a.psd1'; 'L +=' = @('b') }"; 'c.psd1' = "@{ '!merge' = './a.psd1'; 'L +=' = @('c') }" }
        $r.L -join ',' | Should -Be 'a,b,c'
    }

    It 'resolves relative paths from the file they are in' {
        $r = Import-Text "@{ '!merge' = './sub/a.psd1' }" @{ 'sub/a.psd1' = "@{ '!merge' = './b.psd1' }"; 'sub/b.psd1' = "@{ X = 'deep' }" }
        $r.X | Should -Be 'deep'
    }

    It 'keeps single-item and empty lists as lists' {
        $r = Import-Text "@{ '!merge' = './a.psd1'; E2 = '!<E>' }" @{ 'a.psd1' = "@{ One = @('x'); E = @() }" }
        , $r.One | Should -BeOfType [object[]]
        $r.One.Count | Should -Be 1
        , $r.E2 | Should -BeOfType [object[]]
        $r.E2.Count | Should -Be 0
    }

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

Describe 'Includes and namespaces' {
    It 'reads included files only through their namespace' {
        $r = Import-Text "@{ '!include' = './shared.psd1'; Db = '!<shared::Db.Url>' }" @{ 'shared.psd1' = "@{ Db = @{ Host = 'h'; Url = '!<Db.Host>:1'; Owner = '!<@name>' } }" }
        $r.Db | Should -Be 'h:1'
        $r.Contains('Host') | Should -BeFalse
    }

    It 'uses !name as the namespace and @name' {
        (Import-Text "@{ '!include' = './m.psd1'; E = '!<mon::E>' }" @{ 'm.psd1' = "@{ '!name' = 'mon'; E = '!<@name>' }" }).E | Should -Be 'mon'
    }

    It 'reads a merged file before merging through its namespace' {
        (Import-Text "@{ '!merge' = './base.psd1'; P = 2; Old = '!<base::P>' }" @{ 'base.psd1' = '@{ P = 1 }' }).Old | Should -Be 1
    }
}

Describe 'Conditions' {
    It 'support every operator' {
        $r = Import-Text @"
@{
    S = 'dev'; N = 5; L = @('dev', 'x'); F = @{ On = `$true }
    C = @{
        '!if !<S> -eq "dev"' = @{ Eq = 1 }
        '!if !<S> -ne "prod"' = @{ Ne = 1 }
        '!if !<N> -gt 3' = @{ Gt = 1 }
        '!if !<N> -ge 5' = @{ Ge = 1 }
        '!if !<N> -lt 9' = @{ Lt = 1 }
        '!if !<N> -le 5' = @{ Le = 1 }
        '!if !<S> -in !<L>' = @{ In = 1 }
        '!if !<S> -like "d*"' = @{ Like = 1 }
        '!if !<S> -match "^DE"' = @{ Match = 1 }
        '!if !<S> -eq "dev" -and !<N> -eq 5' = @{ And = 1 }
        '!if !<S> -eq "x" -or !<N> -eq 5' = @{ Or = 1 }
        '!if -not !<?F.Off>' = @{ Not = 1 }
        '!if (!<N> -eq 1 -or !<N> -eq 5) -and !<S> -eq "dev"' = @{ Paren = 1 }
        '!if !<?F.On>' = @{ Truth = 1 }
        '!if !<S> -eq "prod"' = @{ Never = 1 }
    }
}
"@
        @($r.C.Keys | Sort-Object) -join ',' | Should -Be 'And,Eq,Ge,Gt,In,Le,Like,Lt,Match,Ne,Not,Or,Paren,Truth'
    }

    It 'see keys from later files, and later files still win' {
        $r = Import-Text "@{ '!merge' = './base.psd1'; Stage = 'prod'; Port = 1 }" @{ 'base.psd1' = "@{ Stage = 'dev'; '!if !<Stage> -eq `"prod`"' = @{ Port = 443; Tls = `$true } }" }
        $r.Tls | Should -BeTrue
        $r.Port | Should -Be 1
    }

    It 'use operators inside a body' {
        (Import-Text "@{ L = @('a'); '!if true' = @{ 'L +=' = @('b') } }").L -join ',' | Should -Be 'a,b'
    }
}

Describe 'Files' {
    It 'reads UTF-8 with and without BOM, and CRLF' {
        $dir = New-TestFiles @{ 'nobom.psd1' = "@{ A = '$([char]0xE4)' }"; 'crlf.psd1' = "@{`r`n    A = 1`r`n    B = '!<A>'`r`n}" }
        $bom = Join-Path $dir 'bom.psd1'
        [IO.File]::WriteAllText($bom, "@{ A = '$([char]0xE4)' }", (New-Object System.Text.UTF8Encoding $true))
        (Import-Psd (Join-Path $dir 'nobom.psd1')).A | Should -Be ([string][char]0xE4)
        (Import-Psd $bom).A | Should -Be ([string][char]0xE4)
        (Import-Psd (Join-Path $dir 'crlf.psd1')).B | Should -Be 1
    }

    It 'ConvertFrom-Psd uses -BasePath for relative paths' {
        $dir = New-TestFiles @{ 'base.psd1' = '@{ A = 1 }' }
        (ConvertFrom-Psd -Text "@{ '!merge' = './base.psd1'; B = '!<A>' }" -BasePath $dir).B | Should -Be 1
    }
}

Describe 'Writing' {
    It 'round-trips' {
        $o = [ordered]@{ S = "it's !<x>"; I = 1; L = [long]5; D = 2.0; M = 1.5d; B = $true; N = $null; E = @(); One = @('x'); Nested = [ordered]@{ 'my.key' = @(1, [ordered]@{ A = 'b' }); '!bang' = 1 } }
        $back = ConvertFrom-Psd -Text (ConvertTo-Psd $o)
        Compare-TestValue $o $back | Should -BeNullOrEmpty
    }

    It 'writes dates, guids, versions, enums and objects' {
        $t = ConvertTo-Psd ([ordered]@{ D = [datetime]'2026-01-02T03:04:05'; G = [guid]'7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'; V = [version]'1.2.3'; E = [System.DayOfWeek]::Monday; O = [pscustomobject]@{ A = 1 } })
        $t | Should -Match "D = '2026-01-02T03:04:05.0000000'"
        $t | Should -Match "G = '7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'"
        $t | Should -Match "V = '1.2.3'"
        $t | Should -Match "E = 'Monday'"
        $t | Should -Match 'O = @\{'
    }

    It 'follows the format options' {
        $t = ConvertTo-Psd ([ordered]@{ Bb = 1; A = @(1, 2, 3); S = 'x' }) -Format @{ Indent = 2; SortKeys = $true; AlignEquals = $true; InlineArrayMax = 2; Quote = 'Double'; LineEnding = 'LF' }
        $t | Should -BeExactly "@{`n  A  = @(`n    1`n    2`n    3`n  )`n  Bb = 1`n  S  = `"x`"`n}"
    }

    It 'Export-Psd writes UTF-8 without BOM by default' {
        $p = Join-Path $TestDrive 'out.psd1'
        Export-Psd @{ A = "$([char]0xE4)" } -Path $p
        $bytes = [IO.File]::ReadAllBytes($p)
        $bytes[0] | Should -Be ([byte][char]'@')
        (Import-Psd $p).A | Should -Be ([string][char]0xE4)
    }
}

Describe 'Keys and values' {
    BeforeAll { $script:c = Import-Text "@{ Stage = 'dev'; Server = @{ Port = 1; Tls = @{ Enabled = `$true; Port = 2 } }; Plugins = @('a', 'b'); Token = 't' }" }
    It 'Test-PsdKey' {
        Test-PsdKey $c -Key Stage, 'Server.Port' | Should -BeTrue
        Test-PsdKey $c -Key Stage, Nope | Should -BeFalse
        Test-PsdKey $c.Server.Tls -Key Enabled, Port -Exact | Should -BeTrue
        Test-PsdKey $c.Server -Key Port -Exact | Should -BeFalse
        Test-PsdKey $c -Key Foo, Stage -Any | Should -BeTrue
        Test-PsdKey $c -Key stage | Should -BeTrue
        Test-PsdKey $c -Key stage -CaseSensitive | Should -BeFalse
    }
    It 'Get-PsdMissingKey and Assert-PsdKey' {
        Get-PsdMissingKey $c -Key Stage, Nope, 'Server.Nope' | Should -Be @('Nope', 'Server.Nope')
        { Assert-PsdKey $c -Key Stage, Nope } | Should -Throw '*Nope*'
        { Assert-PsdKey $c -Key Stage } | Should -Not -Throw
    }
    It 'Get-, Set- and Remove-PsdValue' {
        Get-PsdValue $c -Path 'Server.Tls.Port' | Should -Be 2
        Get-PsdValue $c -Path 'Plugins[-1]' | Should -Be 'b'
        Set-PsdValue $c -Path 'Server.Port' -Value 9
        Set-PsdValue $c -Path 'New.Deep' -Value 'x'
        $c.Server.Port | Should -Be 9
        $c.New.Deep | Should -Be 'x'
        Remove-PsdValue $c -Path 'Token'
        Remove-PsdValue $c -Path 'Plugins[0]'
        $c.Contains('Token') | Should -BeFalse
        $c.Plugins -join ',' | Should -Be 'b'
    }
}

Describe 'Editing files' {
    It 'Update-Psd changes one value and keeps comments' {
        $dir = New-TestFiles @{ 'f.psd1' = "# top`n@{`n    # port`n    Port = 1   # inline`n    Server = @{`n        Host = 'a'`n    }`n}`n" }
        $f = Join-Path $dir 'f.psd1'
        Update-Psd $f -Key Port -Value 2
        Update-Psd $f -Key 'Server.Debug' -Value $true
        $t = [IO.File]::ReadAllText($f)
        $t | Should -Be "# top`n@{`n    # port`n    Port = 2   # inline`n    Server = @{`n        Host = 'a'`n        Debug = `$true`n    }`n}`n"
    }

    It 'Format-Psd re-indents and keeps comments' {
        $dir = New-TestFiles @{ 'f.psd1' = "@{`n# c`n  A = 1`n      B = @{`n  C = 2   `n  }`n}" }
        $f = Join-Path $dir 'f.psd1'
        Format-Psd $f
        [IO.File]::ReadAllText($f) | Should -BeExactly "@{`n    # c`n    A = 1`n    B = @{`n        C = 2`n    }`n}"
    }
}

Describe 'Schema' {
    It 'passes the everything example' {
        Test-Psd (Join-Path $Examples 'everything/app.psd1') | Should -BeTrue
        @(Get-PsdError (Join-Path $Examples 'everything/app.psd1')).Count | Should -Be 0
    }

    It 'checks enums from !types and .NET' {
        $dir = New-TestFiles @{ 'T.psm1' = 'enum Level { Debug; Info }'; 's.psd1' = "@{ '!types' = './T.psm1'; Properties = @{ L = '[Level]'; D = '[System.DayOfWeek]'; V = '[version]' } }" }
        Test-PsdSchema @{ L = 'info'; D = 'Monday'; V = '1.2' } -Schema (Join-Path $dir 's.psd1') | Should -BeTrue
        Test-PsdSchema @{ L = 'Loud' } -Schema (Join-Path $dir 's.psd1') | Should -BeFalse
        (Get-PsdError -InputObject @{ L = 'Loud' } -Schema (Join-Path $dir 's.psd1')).Code | Should -Be 'PSD504'
    }

    It 'Add-PsdDefault fills in missing keys only' {
        $dir = New-TestFiles @{ 's.psd1' = "@{ Properties = @{ A = @{ Type = 'int'; Default = 3 }; B = @{ Type = 'int'; Default = 4 } } }" }
        $o = [ordered]@{ B = 1 }
        Add-PsdDefault $o -Schema (Join-Path $dir 's.psd1')
        $o.A | Should -Be 3
        $o.B | Should -Be 1
    }

    It 'New-PsdSchema infers types' {
        $s = New-PsdSchema -InputObject ([ordered]@{ A = 1; L = @('x'); M = @{ B = $true } })
        $s.Properties.A | Should -Be 'int'
        $s.Properties.L | Should -Be 'string[]'
        $s.Properties.M.Properties.B | Should -Be 'bool'
    }
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

Describe 'Debug commands' {
    It 'Compare-Psd lists changes' {
        $d = Compare-Psd @{ A = 1; B = @(1, 2); C = 'x' } @{ A = 2; B = @(1); D = 'y' }
        ($d | Where-Object Path -eq 'A').Change | Should -Be 'changed'
        ($d | Where-Object Path -eq 'B[1]').Change | Should -Be 'removed'
        ($d | Where-Object Path -eq 'C').Change | Should -Be 'removed'
        ($d | Where-Object Path -eq 'D').Change | Should -Be 'added'
    }

    It 'Get-PsdProvenance shows source and overrides' {
        $p = Get-PsdProvenance (Join-Path $Examples 'config/last.psd1') -Key 'Server.Port'
        $p.Value | Should -Be 9000
        $p.Source | Should -Be 'next.psd1:5:24'
        $p.Overrides | Should -Be 'base.psd1:19:16'
    }

    It 'Resolve-PsdReference shows the steps' {
        $steps = @(Resolve-PsdReference (Join-Path $Examples 'config/last.psd1') -Key 'Service.Title')
        $steps[-1].Value | Should -Be 'LAST (dev)'
        ($steps | Where-Object { $_.Step.Trim() -eq '| upper' }).Value | Should -Be 'LAST'
    }
}
