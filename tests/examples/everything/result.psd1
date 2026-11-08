# What Import-Psd ./app.psd1 returns, worked out by hand. This is plain data.
# Assumes Windows, the files in C:/app/config, and APP_STAGE and APP_PORT not set.
@{
    Plugins  = @('first', 'core', 'auth', 'debug', 'cache')
    CoreName = 'core'

    Literals = @{
        Single   = 'single quotes'
        Double   = 'double quotes'
        Negative = -1
        Decimal  = 1.5
        Hex      = 16
        Size     = 1024
        Yes      = $true
        No       = $false
        Nothing  = $null
        Empty    = @()
        Comma    = @(1, 2, 3)
        One      = @('only')
    }

    Stage   = 'dev'
    Num     = 5
    Stages  = @('dev', 'test')
    Feature = @{ On = $true }

    Builtins = @{
        Name    = 'app'
        File    = 'C:/app/config/app.psd1'
        Dir     = 'C:/app/config'
        Os      = 'windows'
        OwnName = 'defaults'
        OwnFile = 'C:/app/config/defaults.psd1'
        OwnDir  = 'C:/app/config'
    }

    Refs = @{
        Path       = 'single quotes'
        KeepsType  = 1024
        WholeMap   = @{ On = $true }
        WholeList  = @('dev', 'test')
        InText     = 'size=1024 stage=dev'
        NullInText = '[]'
        ThroughRef = 'size=1024 stage=dev'
        FirstItem  = 'dev'
        LastItem   = 'test'
        Escaped    = '!<Not.A.Reference>'
    }

    'dotted.key' = @{ 'with space' = 'found it' }
    'say"hi'     = 'a quote in a key'
    '!literal'   = 'this key is really !literal'

    OddRefs = @{
        Dotted = 'found it'
        Quote  = 'a quote in a key'
        Bang   = 'this key is really !literal'
    }

    Fallbacks = @{
        FromKey  = 'dev'
        Text     = 'none'
        Number   = 5
        IsTrue   = $true
        IsFalse  = $false
        IsNull   = $null
        Chained  = 'last'
        OnNull   = 'was null'
        Optional = $null
    }

    Words = @{
        Mixed  = 'Hello World'
        Padded = '  x  '
        Who    = 'There'
        Csv    = 'a,b,c'
        List   = @('c', 'a', 'c', 'b')
        Map    = @{ A = 1; B = 2 }
    }

    Filters = @{
        Lower   = 'hello world'
        Upper   = 'HELLO WORLD'
        Trim    = 'x'
        Replace = 'Hello There'
        Split   = @('a', 'b', 'c')
        Join    = 'c-a-c-b'
        First   = 'c'
        Last    = 'b'
        Sort    = @('a', 'b', 'c', 'c')
        Unique  = @('c', 'a', 'b')
        Count   = 4
        Keys    = @('A', 'B')
        Values  = @(1, 2)
        Chained = 'hello-world'
    }

    Checks = @{
        Eq        = $true
        Ne        = $true
        Gt        = $true
        Ge        = $true
        Lt        = $true
        Le        = $true
        In        = $true
        Like      = $true
        Match     = $true
        And       = $true
        Or        = $true
        Not       = $true
        Brackets  = $true
        TruthTest = $true
        Os        = $true
        Env       = $true
    }

    Server = @{
        Host  = 'example.local'
        Port  = 9000
        Ports = @(80, 443)
        Url   = 'http://example.local:9000'
    }

    Tags     = @('replaced')
    Features = @('stable')
    Options  = @{ Keep = 1 }
    Legacy   = @{ C = 3 }
    Flexible = @{ Now = 'a map' }
    Nullable = $null
    Replicas = 9

    Typed = @{
        Level    = 'Warn'
        Levels   = @('Info', 'Debug')
        Day      = 'Monday'
        Days     = @('Friday')
        Version  = '1.2.3'
        Id       = '7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'
        When     = '2026-01-01'
        Money    = 1.5
        Anything = @(1, 'two')
        Either   = 'text'
        Maybe    = $null
        Quotas   = @{ Cpu = 4; Ram = 16 }
        Mixed    = @(1, 'a', $true)
    }

    Logging = @{
        Level = 'Info'
        File  = 'C:/app/config/app.log'
    }

    Cache = @{ Size = 10 }

    Hosts   = @('a', 'b')
    NewList = @('x')

    Namespaces = @{
        WholeMap    = @{
            Host   = 'db.internal'
            Port   = 5432
            Url    = 'db.internal:5432'
            Owner  = 'shared'
            Driver = 'pg'
        }
        Field       = 'db.internal:5432'
        Renamed     = 'http://monitoring.internal:9100'
        FromGlob    = 'audit-log'
        MergedFile  = 8080
        ChainBottom = 'core'
        ThisFile    = 'example.local'
        OwnName     = 'app'
    }
}
