BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
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

    It 'can be nested, and the inner one is decided only when the outer one is true' {
        $r = Import-Text "@{ A = 1; '!if !<A> -eq 1' = @{ B = 2; '!if !<A> -eq 1' = @{ C = 3; '!if false' = @{ D = 4 } } } }"
        $r.B | Should -Be 2
        $r.C | Should -Be 3
        $r.Contains('D') | Should -BeFalse
        (Import-Text "@{ '!if false' = @{ B = 2; '!if !<Missing>' = @{ C = 3 } } }").Contains('B') | Should -BeFalse
    }

    It 'can be nested in nested maps' {
        (Import-Text "@{ A = @{ X = 1; '!if true' = @{ B = @{ '!if true' = @{ C = 2 } } } } }").A.B.C | Should -Be 2
    }

    It 'read keys set in another !if, in any order' {
        $r = Import-Text "@{ '!if !<B> -eq 2' = @{ C = 3 }; A = `$true; '!if !<A>' = @{ B = 2 } }"
        $r.C | Should -Be 3
        $r = Import-Text "@{ A = `$true; '!if !<D>' = @{ E = 1 }; '!if !<C>' = @{ D = `$true }; '!if !<A>' = @{ C = `$true } }"
        $r.E | Should -Be 1
    }

    It 'follow references to see what they read' {
        $r = Import-Text "@{ A = `$true; X = '!<B ?? `"off`">'; '!if !<X> -eq `"on`"' = @{ Y = 1 }; '!if !<A>' = @{ B = 'on' } }"
        $r.Y | Should -Be 1
    }

    It 'see the value set by another !if that is true' {
        $r = Import-Text "@{ K = 'a'; A = `$true; '!if !<A>' = @{ K = 'b' }; '!if !<K> -eq `"a`"' = @{ Old = 1 }; '!if !<K> -eq `"b`"' = @{ New = 1 } }"
        $r.Contains('Old') | Should -BeFalse
        $r.New | Should -Be 1
    }

    It 'may read what their own body writes' {
        $r = Import-Text "@{ K = 'a'; '!if !<K> -eq `"a`"' = @{ K = 'b'; Ran = 1 } }"
        $r.K | Should -Be 'b'
        $r.Ran | Should -Be 1
    }

    It 'treat keys of one map separately: Opt.A does not wait for Opt.B' {
        $r = Import-Text "@{ Opt = @{ A = `$true }; '!if !<Opt.A>' = @{ Opt = @{ B = `$true } }; '!if !<Opt.B>' = @{ Done = 1 } }"
        $r.Done | Should -Be 1
    }
}

Describe "'!merge' and '!include' inside !if" {
    It 'merges the file only when the condition is true' {
        $text = "@{ Add = VALUE; '!if !<Add>' = @{ '!merge +=' = './extra.psd1' } }"
        $more = @{ 'extra.psd1' = "@{ E = 1 }" }
        (Import-Text $text.Replace('VALUE', '$true') $more).E | Should -Be 1
        (Import-Text $text.Replace('VALUE', '$false') $more).Contains('E') | Should -BeFalse
    }

    It 'does not read a file behind a false condition, it may not exist' {
        (Import-Text "@{ '!if false' = @{ '!merge +=' = './missing.psd1'; '!include +=' = './missing2.psd1' }; A = 1 }").A | Should -Be 1
    }

    It 'puts the file below the one that merges it, so that file wins' {
        $r = Import-Text "@{ A = 'own'; '!if true' = @{ '!merge +=' = './e.psd1' } }" @{ 'e.psd1' = "@{ A = 'extra'; B = 'extra' }" }
        $r.A | Should -Be 'own'
        $r.B | Should -Be 'extra'
    }

    It 'comes after the normal !merge of the file' {
        $r = Import-Text "@{ '!merge' = './a.psd1'; '!if true' = @{ '!merge +=' = './b.psd1' } }" @{ 'a.psd1' = "@{ K = 'a'; L = @('a') }"; 'b.psd1' = "@{ K = 'b'; 'L +=' = @('b') }" }
        $r.K | Should -Be 'b'
        $r.L -join ',' | Should -Be 'a,b'
    }

    It 'follows the chain of the merged file, with its own conditions' {
        $r = Import-Text "@{ On = `$true; '!if !<On>' = @{ '!merge +=' = './a.psd1' } }" @{ 'a.psd1' = "@{ '!merge' = './b.psd1'; '!if !<On>' = @{ '!merge +=' = './c.psd1' } }"; 'b.psd1' = "@{ B = 1 }"; 'c.psd1' = "@{ C = 1 }" }
        $r.B | Should -Be 1
        $r.C | Should -Be 1
    }

    It 'works in a nested !if' {
        $r = Import-Text "@{ '!if true' = @{ '!if true' = @{ '!merge +=' = './e.psd1' } } }" @{ 'e.psd1' = "@{ E = 1 }" }
        $r.E | Should -Be 1
    }

    It 'loads files first, so other conditions see what those files set' {
        $r = Import-Text "@{ '!if !<?Flag>' = @{ Seen = 1 }; '!if true' = @{ '!merge +=' = './e.psd1' } }" @{ 'e.psd1' = "@{ Flag = `$true }" }
        $r.Seen | Should -Be 1
    }

    It 'allows a merged file to change what its own condition read' {
        $r = Import-Text "@{ '!merge' = './b.psd1'; '!if !<S> -eq `"x`"' = @{ '!merge +=' = './e.psd1' } }" @{ 'b.psd1' = "@{ S = 'x' }"; 'e.psd1' = "@{ S = 'y'; T = 1 }" }
        $r.S | Should -Be 'y'
        $r.T | Should -Be 1
    }

    It 'reads -Include in the condition' {
        $r = Import-Text "@{ '!if !<run::Stage> -eq `"prod`"' = @{ '!merge +=' = './p.psd1' } }" @{ 'p.psd1' = "@{ P = 1 }" } @{ Include = @{ run = @{ Stage = 'prod' } } }
        $r.P | Should -Be 1
    }

    It 'includes a file only when the condition is true' {
        $r = Import-Text "@{ '!if true' = @{ '!include +=' = './shared.psd1' }; S = '!<shared::K>' }" @{ 'shared.psd1' = "@{ K = 'v' }" }
        $r.S | Should -Be 'v'
    }

    It 'works in a .ps1 read through -Loader, and a false branch never runs' {
        $marker = Join-Path $TestDrive 'ran.txt'
        $dir = New-TestFiles @{
            'a.ps1' = "@{ On = `$true; '!if !<On>' = @{ '!merge +=' = './b.ps1' }; '!if false' = @{ '!merge +=' = './c.ps1' } }"
            'b.ps1' = "@{ B = 1 }"
            'c.ps1' = "Set-Content -LiteralPath '$marker' 'x'; @{ C = 1 }"
        }
        $r = Import-Psd (Join-Path $dir 'a.ps1') -Loader { param($Path) & $Path }
        $r.B | Should -Be 1
        $r.Contains('C') | Should -BeFalse
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'is an error in a map given to Merge-Psd' {
        $dir = New-TestFiles @{}
        Get-ErrorCode { Merge-Psd @{ '!if true' = @{ '!merge +=' = './x.psd1' } } } $dir | Should -Contain 'PSD206'
    }

    It 'checks Keys only after all files are loaded' {
        $r = Import-Text "@{ '!merge' = @{ Path = './a.psd1'; Keys = 'K' } }" @{ 'a.psd1' = "@{ '!if true' = @{ K = 1 } }" }
        $r.K | Should -Be 1
    }

    It 'gives PSD201 for a circle through a condition' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ '!if true' = @{ '!merge +=' = './b.psd1' } }"; 'b.psd1' = "@{ '!merge' = './a.psd1' }" }
        Get-ErrorCode { Import-Psd ./a.psd1 } $dir | Should -Contain 'PSD201'
    }

    It 'gives PSD200 for a missing file behind a true condition' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ '!if true' = @{ '!merge +=' = './no.psd1' } }" }
        Get-ErrorCode { Import-Psd ./a.psd1 } $dir | Should -Contain 'PSD200'
    }
}

Describe "Operators on '!merge' and '!include'" {
    BeforeAll {
        $script:more = @{ 'a.psd1' = "@{ A = 1; K = 'a' }"; 'b.psd1' = "@{ B = 1; K = 'b' }"; 'c.psd1' = "@{ C = 1; K = 'c' }" }
        function script:Get-MergedOrder {
            param([string] $Body)
            $dir = New-TestFiles (@{ 'main.psd1' = "@{ '!merge' = @('./a.psd1', './b.psd1'); '!if true' = @{ $Body } }" } + $script:more)
            @((Get-PsdLoadPlan (Join-Path $dir 'main.psd1')).Files | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Where-Object { $_ -ne 'main' }) -join ','
        }
    }

    It "<Key> = <Value> gives <Expected>" -ForEach @(
        @{ Key = "'!merge +='"; Value = "'./c.psd1'"; Expected = 'a,b,c' }
        @{ Key = "'!merge =+'"; Value = "'./c.psd1'"; Expected = 'c,a,b' }
        @{ Key = "'!merge :='"; Value = "'./c.psd1'"; Expected = 'c' }
        @{ Key = "'!merge |='"; Value = "@('./a.psd1', './c.psd1')"; Expected = 'a,b,c' }
        @{ Key = "'!merge -='"; Value = "'./a.psd1'"; Expected = 'b' }
        @{ Key = "'!merge -='"; Value = '$true'; Expected = '' }
        @{ Key = "'!merge[0] :='"; Value = "'./c.psd1'"; Expected = 'c,b' }
        @{ Key = "'!merge[-1] :='"; Value = "'./c.psd1'"; Expected = 'a,c' }
        @{ Key = "'!merge[0] -='"; Value = '$true'; Expected = 'b' }
        @{ Key = "'!merge[1] +='"; Value = "'./c.psd1'"; Expected = 'a,c,b' }
        @{ Key = "'!merge[69] +='"; Value = "'./c.psd1'"; Expected = 'a,b,c' }
        @{ Key = "'!merge[-1] +='"; Value = "'./c.psd1'"; Expected = 'a,b,c' }
        @{ Key = '"!merge[''./a.psd1''] :="'; Value = "'./c.psd1'"; Expected = 'c,b' }
        @{ Key = '"!merge[''./b.psd1''] -="'; Value = '$true'; Expected = 'a' }
    ) {
        Get-MergedOrder "$Key = $Value" | Should -Be $Expected
    }

    It 'works at the top of a file, after the plain key' {
        $r = Import-Text "@{ '!merge' = './a.psd1'; '!merge +=' = './b.psd1' }" $more
        $r.A | Should -Be 1
        $r.K | Should -Be 'b'
    }

    It 'runs the operators of several !if in order' {
        $r = Import-Text "@{ '!merge' = './a.psd1'; '!if true' = @{ '!merge +=' = './b.psd1' }; 'X' = 1; '!if 1 -eq 1' = @{ '!merge -=' = './a.psd1' } }" $more
        $r.Contains('A') | Should -BeFalse
        $r.B | Should -Be 1
    }

    It 'changes !include too' {
        $r = Import-Text "@{ '!include' = './a.psd1'; '!if true' = @{ '!include :=' = './b.psd1' }; V = '!<b::B>' }" $more
        $r.V | Should -Be 1
    }

    It 'does nothing when the condition is false' {
        (Import-Text "@{ '!merge' = './a.psd1'; '!if false' = @{ '!merge :=' = './b.psd1' } }" $more).K | Should -Be 'a'
    }

    It 'takes references in the paths' {
        (Import-Text "@{ N = 'c'; '!if true' = @{ '!merge +=' = './!<N>.psd1' } }" $more).C | Should -Be 1
    }

    It 'gives <Code> for <Case>' -ForEach @(
        @{ Case = 'a plain !merge inside an !if'; Code = 'PSD206'; Text = "@{ '!if true' = @{ '!merge' = './a.psd1' } }" }
        @{ Case = 'a plain !include inside an !if'; Code = 'PSD206'; Text = "@{ '!if true' = @{ '!include' = './a.psd1' } }" }
        @{ Case = 'an operator in a nested map'; Code = 'PSD206'; Text = "@{ X = @{ '!merge +=' = './a.psd1' } }" }
        @{ Case = 'a path not in the list'; Code = 'PSD212'; Text = "@{ '!merge' = './a.psd1'; '!if true' = @{ '!merge -=' = './b.psd1' } }" }
        @{ Case = 'an index not in the list'; Code = 'PSD212'; Text = "@{ '!merge' = './a.psd1'; '!if true' = @{ '!merge[5] :=' = './b.psd1' } }" }
        @{ Case = 'a value not in the list'; Code = 'PSD212'; Text = "@{ '!merge' = './a.psd1'; '!if true' = @{ `"!merge['./b.psd1'] -=`" = `$true } }" }
        @{ Case = '-= with an index and no $true'; Code = 'PSD211'; Text = "@{ '!merge' = './a.psd1'; '!if true' = @{ '!merge[0] -=' = './a.psd1' } }" }
        @{ Case = '=+ with an index'; Code = 'PSD209'; Text = "@{ '!if true' = @{ '!merge[0] =+' = './a.psd1' } }" }
        @{ Case = 'an operator on another directive'; Code = 'PSD205'; Text = "@{ '!schema +=' = './a.psd1' }" }
    ) {
        $dir = New-TestFiles (@{ 'main.psd1' = $Text } + $more)
        Get-ErrorCode { Import-Psd ./main.psd1 } $dir | Should -Contain $Code
    }
}

Describe 'References in paths' {
    It 'work in !merge' {
        $r = Import-Text "@{ Stage = 'prod'; '!merge' = './!<Stage>.psd1' }" @{ 'prod.psd1' = "@{ P = 1 }" }
        $r.P | Should -Be 1
    }

    It 'work in !include and with Keys' {
        $r = Import-Text "@{ N = 'x'; '!include' = './!<N>.psd1'; V = '!<x::K>' }" @{ 'x.psd1' = "@{ K = 'v' }" }
        $r.V | Should -Be 'v'
        $r = Import-Text "@{ N = 'x'; '!merge' = @{ Path = './!<N>.psd1'; Keys = 'K' } }" @{ 'x.psd1' = "@{ K = 'v'; Other = 1 }" }
        $r.K | Should -Be 'v'
        $r.Contains('Other') | Should -BeFalse
    }

    It 'read -Include' {
        $r = Import-Text "@{ '!merge' = './!<run::Stage>.psd1' }" @{ 'prod.psd1' = "@{ P = 1 }" } @{ Include = @{ run = @{ Stage = 'prod' } } }
        $r.P | Should -Be 1
    }

    It 'wait for a condition that writes what they read' {
        $r = Import-Text "@{ '!merge' = './!<F>.psd1'; F = 'a'; A = `$true; '!if !<A>' = @{ F = 'b' } }" @{ 'a.psd1' = "@{ V = 'a' }"; 'b.psd1' = "@{ V = 'b' }" }
        $r.V | Should -Be 'b'
    }

    It 'work inside an !if' {
        $r = Import-Text "@{ N = 'x'; '!if true' = @{ '!merge +=' = './!<N>.psd1' } }" @{ 'x.psd1' = "@{ K = 1 }" }
        $r.K | Should -Be 1
    }

    It 'give PSD301 for a missing key and PSD200 for a missing file' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ '!merge' = './!<Nope>.psd1' }"; 'b.psd1' = "@{ N = 'no'; '!merge' = './!<N>.psd1' }" }
        Get-ErrorCode { Import-Psd ./a.psd1 } $dir | Should -Contain 'PSD301'
        Get-ErrorCode { Import-Psd ./b.psd1 } $dir | Should -Contain 'PSD200'
    }

    It 'stay an error in !schema' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ N = 'x'; '!schema' = './!<N>.psd1' }" }
        Get-ErrorCode { Import-Psd ./a.psd1 } $dir | Should -Contain 'PSD206'
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

    It 'also works on <Name>' -ForEach @(
        @{ Name = 'Test-Psd'; Run = { Test-Psd ./app.psd1 -Include @{ run = @{ Root = 'r' } } }; Want = 'True' }
        @{ Name = 'Get-PsdError'; Run = { @(Get-PsdError ./app.psd1 -Include @{ run = @{ Root = 'r' } }).Count }; Want = '0' }
        @{ Name = 'Get-PsdProvenance'; Run = { (Get-PsdProvenance ./app.psd1 -Key A -Include @{ run = @{ Root = 'r' } }).Value }; Want = 'r' }
        @{ Name = 'Resolve-PsdReference'; Run = { @(Resolve-PsdReference ./app.psd1 -Key A -Include @{ run = @{ Root = 'r' } })[-1].Value }; Want = 'r' }
    ) {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ A = '!<run::Root>' }" }
        Push-Location $dir
        try { "$(& $Run)" | Should -Be $Want }
        finally { Pop-Location }
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

Describe 'References without a name read the includes' {
    It 'reads a key only an include has, as if the name were written: <Case>' -ForEach @(
        @{ Case = '!include'; Files = @{ 'app.psd1' = "@{ '!include' = './shared.psd1'; A = '!<Db>' }"; 'shared.psd1' = "@{ Db = 'pg' }" }; Include = $null }
        @{ Case = '-Include'; Files = @{ 'app.psd1' = "@{ A = '!<Db>' }" }; Include = @{ run = @{ Db = 'pg' } } }
    ) {
        $dir = New-TestFiles $Files
        $r = if ($Include) { Import-Psd (Join-Path $dir 'app.psd1') -Include $Include } else { Import-Psd (Join-Path $dir 'app.psd1') }
        $r.A | Should -Be 'pg'
        $r.Contains('Db') | Should -BeFalse
    }

    It 'reads deeper paths and keeps the type' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ A = '!<Server.Port>'; B = 'p=!<Server.Port>' }" }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include @{ run = @{ Server = @{ Port = 80 } } }
        $r.A | Should -BeOfType [int]
        $r.B | Should -Be 'p=80'
    }

    It 'the file and its merge chain come first' {
        $dir = New-TestFiles @{ 'base.psd1' = "@{ Db = 'base' }"; 'app.psd1' = "@{ '!merge' = './base.psd1'; A = '!<Db>' }" }
        (Import-Psd (Join-Path $dir 'app.psd1') -Include @{ run = @{ Db = 'run' } }).A | Should -Be 'base'
    }

    It 'works in conditions' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ '!if !<Stage> -eq `"prod`"' = @{ R = 3 } }" }
        (Import-Psd (Join-Path $dir 'app.psd1') -Include @{ run = @{ Stage = 'prod' } }).R | Should -Be 3
    }

    It 'is PSD313 when several includes have the key and the file does not' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ '!include' = './shared.psd1'; A = '!<Db>' }"; 'shared.psd1' = "@{ Db = 'pg' }" }
        $t = Get-ErrorText { Import-Psd ./app.psd1 -Include @{ run = @{ Db = 'x' } } } $dir
        "$t" | Should -Match 'PSD313'
        "$t" | Should -Match '!<run::Db>'
        "$t" | Should -Match '!<shared::Db>'
    }

    It 'is PSD301 with a suggestion from the includes when nothing has it' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ Name = 'x'; A = '!<Stgae>' }" }
        $t = Get-ErrorText { Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'x' } } } $dir
        "$t" | Should -Match 'PSD301'
        "$t" | Should -Match "Did you mean 'Stage'"
    }

    It 'tells with -Verbose where a value came from when an include has the key too' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{`n    Inst = 'mine'`n    A = '!<Inst>\x'`n}" }
        $out = @(Import-Psd (Join-Path $dir 'app.psd1') -Include @{ config = @{ Inst = 'cfg' } } -Verbose 4>&1)
        $notes = @($out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        $notes.Count | Should -Be 1
        $notes[0] | Should -Match 'app\.psd1, line 3: !<Inst> reads Inst from this file and its merge chain\. The include config has Inst too; !<config::Inst> reads that one\.'
        ($out | Where-Object { $_ -is [System.Collections.IDictionary] }).A | Should -Be 'mine\x'
    }

    It 'is quiet without -Verbose' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ Inst = 'mine'; A = '!<Inst>' }" }
        @(Import-Psd (Join-Path $dir 'app.psd1') -Include @{ config = @{ Inst = 'cfg' } } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
    }

    It 'PSD301 for a deeper key names the include that has it and why it was not read' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ Options = @{ A = 1 }; X = '!<Options.Tools>' }" }
        $t = Get-ErrorText { Import-Psd ./app.psd1 -Include @{ config = @{ Options = @{ Tools = 't' } } } } $dir
        "$t" | Should -Match 'PSD301'
        "$t" | Should -Match 'The include config has Options\.Tools: !<config::Options\.Tools> reads it\.'
        "$t" | Should -Match 'Without name::, Options is read from this file and its merge chain'
    }

    It 'PSD301 for a deeper key read from an include says so' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ X = '!<Server.Prot>' }" }
        $t = Get-ErrorText { Import-Psd ./app.psd1 -Include @{ config = @{ Server = @{ Port = 1 } } } } $dir
        "$t" | Should -Match "doesn't exist under Server in the include config"
        "$t" | Should -Match "Did you mean 'Port'"
        "$t" | Should -Match 'so it was read from the include config'
    }
    It 'a fallback ?? and an optional ? still work when nothing has it' {
        $dir = New-TestFiles @{ 'app.psd1' = "@{ A = '!<Nope ?? 1>'; B = '!<?Nope>' }" }
        $r = Import-Psd (Join-Path $dir 'app.psd1') -Include @{ run = @{ X = 1 } }
        $r.A | Should -Be 1
        $r.B | Should -BeNullOrEmpty
    }
}

Describe '-Loader reads scripts, and !merge and !include reach them' {
    BeforeAll {
        $script:run = { param($Path) & $Path }
    }

    It 'loads a .ps1 as the entry file' {
        $dir = New-TestFiles @{ 'app.ps1' = "@{ A = 1; B = '!<A>' }" }
        $r = Import-Psd (Join-Path $dir 'app.ps1') -Loader $run
        $r.B | Should -Be 1
    }

    It '!merge reaches a .ps1, and a .ps1 can !merge, with paths relative to its folder' {
        $dir = New-TestFiles @{
            'base\base.ps1' = "@{ Tags = @('a'); Name = 'base' }"
            'mid\mid.ps1'   = "@{ '!merge' = '../base/base.ps1'; 'Tags +=' = @('b') }"
            'top.psd1'      = "@{ '!merge' = './mid/mid.ps1'; 'Tags +=' = @('c'); From = '!<base::Name>' }"
        }
        $r = Import-Psd (Join-Path $dir 'top.psd1') -Loader $run
        $r.Tags -join ',' | Should -Be 'a,b,c'
        $r.From | Should -Be 'base'
    }

    It '!include reaches a .ps1, and !name in it names it' {
        $dir = New-TestFiles @{ 'shared.ps1' = "@{ '!name' = 'common'; Db = 'pg' }"; 'app.psd1' = "@{ '!include' = './shared.ps1'; A = '!<common::Db>' }" }
        (Import-Psd (Join-Path $dir 'app.psd1') -Loader $run).A | Should -Be 'pg'
    }

    It 'Merge-Psd takes .ps1 paths' {
        $dir = New-TestFiles @{ 'a.ps1' = "@{ A = 1 }"; 'b.ps1' = "@{ '!merge' = './a.ps1'; B = 2 }" }
        $r = Merge-Psd (Join-Path $dir 'b.ps1') -Loader $run
        $r.A | Should -Be 1
        $r.B | Should -Be 2
    }

    It 'runs each script once, even when it is reached twice' {
        $dir = New-TestFiles @{ 'base.ps1' = "@{ A = 1 }"; 'x.psd1' = "@{ '!merge' = './base.ps1' }"; 'top.psd1' = "@{ '!merge' = './base.ps1', './x.psd1' }" }
        $script:calls = 0
        $count = { param($Path) $script:calls++; & $Path }
        $null = Import-Psd (Join-Path $dir 'top.psd1') -Loader $count
        $script:calls | Should -Be 1
    }

    It 'is PSD108 for <Case>' -ForEach @(
        @{ Case = 'a .ps1 without -Loader'; Body = "@{ A = 1 }"; Loader = $null }
        @{ Case = 'a loader that gives two values'; Body = "@{ A = 1 }; @{ B = 2 }"; Loader = { param($Path) & $Path } }
        @{ Case = 'a loader that gives no map'; Body = "'text'"; Loader = { param($Path) & $Path } }
        @{ Case = 'a loader that throws'; Body = "throw 'broken'"; Loader = { param($Path) & $Path } }
    ) {
        $dir = New-TestFiles @{ 's.ps1' = $Body; 'app.psd1' = "@{ '!merge' = './s.ps1' }" }
        $l = $Loader
        if ($l) { Get-ErrorCode { Import-Psd ./app.psd1 -Loader $l } $dir | Should -Contain 'PSD108' }
        else { Get-ErrorCode { Import-Psd ./app.psd1 } $dir | Should -Contain 'PSD108' }
    }
}