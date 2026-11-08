# A config written as a script, with autocomplete from the generated types.
#
#   Export-Psd -InputObject (& ./app.config.ps1) -Path ./app.psd1
#
# Run it from this folder: on 5.1, the path below starts at the working directory.
using module ./App.Types.psm1

$port = 9000

# On PowerShell 7, keys complete inside typed literals: [App]@{ <TAB>
# Every nested map needs its own cast to complete.
[App]@{
    Stage   = [AppStage]::prod
    Service = [AppService]@{
        Name  = 'billing'
        Title = '!<Service.Name | upper>'       # references fit in string properties
    }
    Server  = [AppServer]@{
        Host = 'example.local'
        Port = $port                            # int property: use a real variable
        Tls  = [AppServerTls]@{ Enabled = $true; Port = $port }
    }
    Logging = [AppLogging]@{ Level = [LogLevel]::Warn }
    Plugins = 'core', 'auth'
}

# On PowerShell 5.1, keys only complete inside literals after this script has run
# once in the session. Properties always complete:
#
#   $server = [AppServer]::new()
#   $server.<TAB>
#
#   $config = [App]::new()
#   $config.Server = $server
#   $config
