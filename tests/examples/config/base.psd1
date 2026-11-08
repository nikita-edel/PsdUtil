# Bottom of the chain: base <- next <- last.
@{
    # env: with a fallback
    Stage = '!<env:APP_STAGE ?? "dev">'

    Service = @{
        Name   = '!<@name>'                         # last file in the chain: 'last'
        Origin = '!<this::@name>'                   # this file: 'base'
        Title  = '!<Service.Name | upper> (!<Stage>)'
    }

    Paths = @{
        Root = '!<@dir>/data'
        Logs = '!<Paths.Root>/logs'
    }

    Server = @{
        Host = 'localhost'
        Port = 8080
        Url  = 'http://!<Server.Host>:!<Server.Port>'   # uses the final Host and Port
        Tls  = @{
            Enabled = $false
            Port    = '!<Server.Port>'              # stays an int
        }
    }

    Plugins     = @('core', 'auth')
    Tags        = @('a', 'b')
    Features    = @('beta', 'stable')
    FirstPlugin = '!<Plugins[0]>'
    PluginList  = '!<Plugins | join(",")>'  # filter

    Token = '!<?Vault.Token>'                       # optional: $null when missing
    Note  = 'a literal !!<Name> needs the escape'

    Legacy     = @{ A = 1; B = 2 }
    Deprecated = 'removed by next.psd1'

    # The body merges into this map, in this file's layer.
    '!if !<Stage> -eq "prod"' = @{
        Server           = @{ Port = 443; Tls = @{ Enabled = $true } }
        'Plugins +='     = @('metrics')
    }
}
