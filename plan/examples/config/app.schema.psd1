# Schema for last.psd1.
@{
    '!types' = './Types.psm1'

    Description = 'Service configuration.'

    Properties = @{
        Stage = @{
            Type        = 'string'
            Enum        = 'dev', 'test', 'prod'
            Default     = 'dev'
            Description = 'Deployment stage.'
        }

        Service = @{
            Type       = 'map'
            Required   = $true
            Properties = @{
                Name   = @{ Type = 'string'; Required = $true; Pattern = '^[a-z][a-z0-9-]*$' }
                Origin = 'string'
                Title  = 'string'
            }
        }

        Paths = @{
            Type       = 'map'
            Properties = @{ Root = 'string'; Logs = 'string' }
        }

        Server = @{
            Type       = 'map'
            Required   = $true
            Properties = @{
                Host = @{ Type = 'string'; Required = $true }
                Port = @{ Type = 'int'; Min = 1; Max = 65535; Description = 'TCP port.' }
                Url  = 'string'
                Tls  = @{
                    Type       = 'map'
                    Properties = @{ Enabled = 'bool'; Port = 'int' }
                }
            }
        }

        Plugins     = @{ Type = 'string[]'; Min = 1 }
        Tags        = 'string[]'
        Features    = 'string[]'
        FirstPlugin = 'string'
        PluginList  = 'string'
        Token       = @{ Type = 'string', 'null' }
        Note        = 'string'

        # A map with free keys. Every value must be an int.
        Legacy = @{ Type = 'map'; Items = 'int' }

        Logging = @{
            Type       = 'map'
            Properties = @{
                Level = '[LogLevel]'    # every member of the enum in Types.psm1
                File  = 'string'
            }
        }

        # Allowed to be either a connection string or a map.
        Database = @{
            Type       = 'string', 'map'
            Properties = @{ Host = 'string'; Port = 'int'; Url = 'string'; Owner = 'string' }
        }

        DbUrl    = 'string'
        Metrics  = 'string'
        BasePort = 'int'
        OwnHost  = 'string'
    }
}
