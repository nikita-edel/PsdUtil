# Schema for app.psd1, using every keyword and every kind of type.
@{
    '!types'   = './Types.psm1'                 # where LogLevel is defined
    '!include' = './parts.schema.psd1'          # schemas can include and reference too

    Description  = 'Everything example.'
    AllowUnknown = $true                        # keys not listed below are fine at this level

    Properties = @{
        Stage = @{
            Type        = 'string'
            Enum        = 'dev', 'test', 'prod'
            Default     = 'dev'
            Description = 'Deployment stage.'
        }

        Num      = @{ Type = 'int'; Min = 0; Max = 10 }
        Replicas = 'int'                        # short form
        Retries  = @{ Type = 'int'; Default = 3 }

        Plugins = @{ Type = 'string[]'; Min = 1; Max = 20 }
        Feature = @{ Type = 'map'; Properties = @{ On = 'bool' } }

        Builtins = @{
            Type         = 'map'
            AllowUnknown = $true
            Properties   = @{
                Name = @{ Type = 'string'; Required = $true; Pattern = '^[a-z-]+$'; Min = 2; Max = 32 }
            }
        }

        Server = @{
            Type       = 'map'
            Required   = $true
            Properties = @{
                Host  = @{ Type = 'string'; Required = $true }
                Port  = @{ Type = 'int'; Min = 1; Max = 65535; Description = 'TCP port.' }
                Ports = @{ Type = 'array'; Items = 'int' }
                Url   = 'string'
            }
        }

        Flexible = @{ Type = 'string', 'map' }  # either one
        Nullable = 'null'

        Typed = @{
            Type       = 'map'
            Properties = @{
                Level    = '[LogLevel]'         # your own enum
                Levels   = '[LogLevel][]'       # a list of it
                Day      = '[System.DayOfWeek]' # a .NET enum
                Days     = '[System.DayOfWeek][]'
                Version  = '[version]'
                Id       = '[guid]'
                When     = '[datetime]'
                Money    = 'double'
                Anything = 'any'
                Either   = @{ Type = 'string', 'int' }
                Maybe    = @{ Type = 'string', 'null' }
                Quotas   = @{ Type = 'map'; Items = 'int' }
                Mixed    = 'array'
            }
        }

        Namespaces = @{
            Type         = 'map'
            AllowUnknown = $true
            Properties   = @{ WholeMap = '!<parts.schema::Database>' }    # the reusable piece
        }
    }
}
