# Found by the glob in last.psd1. The namespace comes from !name, not the file name.
@{
    '!name' = 'monitoring'

    Endpoint = 'http://!<@name>.internal:9100'
}
