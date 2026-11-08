# Values, references, filters and conditions.
@{
    '!merge' = './core.psd1'                        # !merge with one path

    # ----- Every kind of value ------------------------------------------------

    Literals = @{
        Single   = 'single quotes'
        Double   = "double quotes"
        Negative = -1
        Decimal  = 1.5
        Hex      = 0x10
        Size     = 1kb
        Yes      = $true
        No       = $false
        Nothing  = $null
        Empty    = @()
        Comma    = 1, 2, 3
        One      = @('only')
    }

    # ----- Settings the conditions look at ------------------------------------

    Stage   = '!<env:APP_STAGE ?? "dev">'
    Num     = 1                                     # app.psd1 sets this to 5
    Stages  = @('dev', 'test')
    Feature = @{ On = $true }

    # ----- Built-ins ----------------------------------------------------------

    Builtins = @{
        Name    = '!<@name>'                        # the last file: app
        File    = '!<@file>'
        Dir     = '!<@dir>'
        Os      = '!<@os>'
        OwnName = '!<this::@name>'                  # the file this is written in
        OwnFile = '!<this::@file>'
        OwnDir  = '!<this::@dir>'
    }

    # ----- References ---------------------------------------------------------

    Refs = @{
        Path       = '!<Literals.Single>'
        KeepsType  = '!<Literals.Size>'             # stays a number
        WholeMap   = '!<Feature>'
        WholeList  = '!<Stages>'
        InText     = 'size=!<Literals.Size> stage=!<Stage>'
        NullInText = '[!<Literals.Nothing>]'
        ThroughRef = '!<Refs.InText>'
        FirstItem  = '!<Stages[0]>'
        LastItem   = '!<Stages[-1]>'
        Escaped    = '!!<Not.A.Reference>'
    }

    # ----- Unusual keys -------------------------------------------------------

    'dotted.key' = @{ 'with space' = 'found it' }
    'say"hi'     = 'a quote in a key'
    '!!literal'  = 'this key is really !literal'

    OddRefs = @{
        Dotted = '!<"dotted.key"."with space">'
        Quote  = '!<"say""hi">'
        Bang   = '!<"!literal">'
    }

    # ----- Fallbacks ----------------------------------------------------------

    Fallbacks = @{
        FromKey  = '!<Missing ?? Stage>'
        Text     = '!<Missing ?? "none">'
        Number   = '!<Missing ?? 5>'
        IsTrue   = '!<Missing ?? true>'
        IsFalse  = '!<Missing ?? false>'
        IsNull   = '!<Missing ?? null>'
        Chained  = '!<Missing ?? AlsoMissing ?? "last">'
        OnNull   = '!<Literals.Nothing ?? "was null">'
        Optional = '!<?Missing>'
    }

    # ----- Filters ------------------------------------------------------------

    Words = @{
        Mixed  = 'Hello World'
        Padded = '  x  '
        Who    = 'There'
        Csv    = 'a,b,c'
        List   = @('c', 'a', 'c', 'b')
        Map    = @{ A = 1; B = 2 }
    }

    Filters = @{
        Lower   = '!<Words.Mixed | lower>'
        Upper   = '!<Words.Mixed | upper>'
        Trim    = '!<Words.Padded | trim>'
        Replace = '!<Words.Mixed | replace("World", Words.Who)>'
        Split   = '!<Words.Csv | split(",")>'
        Join    = '!<Words.List | join("-")>'
        First   = '!<Words.List | first>'
        Last    = '!<Words.List | last>'
        Sort    = '!<Words.List | sort>'
        Unique  = '!<Words.List | unique>'
        Count   = '!<Words.List | count>'
        Keys    = '!<Words.Map | keys>'
        Values  = '!<Words.Map | values>'
        Chained = '!<Words.Mixed | lower | replace(" ", "-")>'
    }

    # ----- Conditions, each adds one key when true ----------------------------

    Checks = @{
        '!if !<Stage> -eq "dev"'                    = @{ Eq = $true }
        '!if !<Stage> -ne "prod"'                   = @{ Ne = $true }
        '!if !<Num> -gt 3'                          = @{ Gt = $true }       # sees the 5 from app.psd1
        '!if !<Num> -ge 5'                          = @{ Ge = $true }
        '!if !<Num> -lt 9'                          = @{ Lt = $true }
        '!if !<Num> -le 5'                          = @{ Le = $true }
        '!if !<Stage> -in !<Stages>'                = @{ In = $true }
        '!if !<Stage> -like "d*"'                   = @{ Like = $true }
        '!if !<Stage> -match "^de"'                 = @{ Match = $true }
        '!if !<Stage> -eq "dev" -and !<Num> -gt 3'  = @{ And = $true }
        '!if !<Stage> -eq "prod" -or !<Num> -gt 3'  = @{ Or = $true }
        '!if -not !<?Feature.Off>'                  = @{ Not = $true }
        '!if (!<Num> -eq 1 -or !<Num> -eq 5) -and !<Stage> -eq "dev"' = @{ Brackets = $true }
        '!if !<?Feature.On>'                        = @{ TruthTest = $true }
        '!if !<@os> -eq "windows"'                  = @{ Os = $true }
        '!if !<env:APP_STAGE ?? "dev"> -eq "dev"'   = @{ Env = $true }
        '!if !<Stage> -eq "prod"'                   = @{ Never = $true }    # false, so no key
    }

    # ----- What the later files change ----------------------------------------

    'Plugins +=' = @('auth')                        # adds to the list in core.psd1

    Server = @{
        Host  = 'localhost'
        Port  = 8080
        Ports = @(80)
        Url   = 'http://!<Server.Host>:!<Server.Port>'
    }

    Tags     = @('a', 'b')
    Features = @('beta', 'stable')
    Options  = @{ Keep = 1; Old = 2 }
    Legacy   = @{ A = 1; B = 2 }
    Gone     = 'deleted by app.psd1'
    Flexible = 'text here, a map in app.psd1'
    Nullable = 'set to $null in app.psd1'

    # A true !if goes in this file's layer, so app.psd1 still beats it.
    '!if !<Stage> -eq "dev"' = @{
        Replicas     = 2
        'Plugins +=' = @('debug')
    }

    # ----- Values the schema checks -------------------------------------------

    Typed = @{
        Level    = 'Warn'
        Levels   = @('Info', 'Debug')
        Day      = 'Monday'
        Days     = @('Friday')
        Version  = '1.2.3'
        Id       = '7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'
        When     = '2026-01-01'
        Money    = 1.5
        Anything = 1, 'two'
        Either   = 'text'
        Maybe    = $null
        Quotas   = @{ Cpu = 4; Ram = 16 }
        Mixed    = 1, 'a', $true
    }
}
