# Top of the chain. This is the file you import: Import-Psd ./app.psd1
@{
    '!merge' = @(
        './defaults.psd1',                                      # a path
        './overlays/*.psd1',                                    # a glob
        @{ Path = './partial.psd1'; Keys = 'Logging', 'Cache' } # only certain keys
    )
    '!include' = @('./shared.psd1', './conf.d/*.psd1')          # a path and a glob
    '!schema'  = './app.schema.psd1'

    # Plain values on top of the earlier files.
    Num      = 5
    Replicas = 9                                                # beats the !if in defaults.psd1
    Flexible = @{ Now = 'a map' }                               # changing type is allowed
    Nullable = $null                                            # sets it to $null, doesn't delete it

    Server = @{
        Host      = 'example.local'                             # deep merge
        'Ports +=' = @(443)                                     # an operator on a nested key
    }

    # Merge operators.
    'Features -=' = @('beta')                                   # remove items from a list
    'Options -='  = @('Old')                                    # remove keys from a map
    'Gone -='     = $true                                       # delete the key
    'Legacy :='   = @{ C = 3 }                                  # replace the whole map

    # Operators also work within one file, and on new keys.
    Hosts        = @('a')
    'Hosts +='   = @('b')
    'NewList +=' = @('x')

    # Namespaces.
    Namespaces = @{
        WholeMap    = '!<shared::Database>'                     # included file, whole map
        Field       = '!<shared::Database.Url>'                 # included file, one value
        Renamed     = '!<monitoring::Endpoint>'                 # namespace from !name
        FromGlob    = '!<audit::Sink>'                          # namespace from the file name
        MergedFile  = '!<defaults::Server.Port>'                # that file's own value
        ChainBottom = '!<core::CoreName>'
        ThisFile    = '!<this::Server.Host>'                    # this file's own value
        OwnName     = '!<this::@name>'
    }
}
