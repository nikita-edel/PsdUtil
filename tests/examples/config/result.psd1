# What Import-Psd ./last.psd1 returns, worked out by hand.
# Assumes the files are in C:/app/config and APP_STAGE is not set.
@{
    Stage = 'dev'

    Service = @{
        Name   = 'last'
        Origin = 'base'
        Title  = 'LAST (dev)'
    }

    Paths = @{
        Root = 'C:/app/config/data'
        Logs = 'C:/app/config/data/logs'
    }

    Server = @{
        Host = 'example.local'
        Port = 9000
        Url  = 'http://example.local:9000'
        Tls  = @{
            Enabled = $false
            Port    = 9000
        }
    }

    Plugins     = @('core', 'auth', 'cache')
    Tags        = @('x')
    Features    = @('stable')
    FirstPlugin = 'core'
    PluginList  = 'core,auth,cache'

    Token = $null
    Note  = 'a literal !<Name> needs the escape'

    Legacy = @{ C = 3 }

    Logging = @{
        Level = 'Info'
        File  = 'C:/app/config/data/logs/last.log'
    }

    Database = @{
        Host  = 'db.internal'
        Port  = 5432
        Url   = 'db.internal:5432'
        Owner = 'shared'
    }

    DbUrl    = 'postgres://db.internal:5432/last'
    Metrics  = 'http://monitoring.internal:9100'
    BasePort = 8080
    OwnHost  = 'example.local'
}
