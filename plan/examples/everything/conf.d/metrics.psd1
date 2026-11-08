# Found by the glob in app.psd1. !name sets the namespace and @name.
@{
    '!name' = 'monitoring'

    Endpoint = 'http://!<@name>.internal:9100'
}
