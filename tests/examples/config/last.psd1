# Top of the chain. This is the file you import.
@{
    '!merge'   = @('./next.psd1', @{ Path = './extra.psd1'; Keys = 'Logging' })
    '!include' = @('./shared.psd1', './conf.d/*.psd1')
    '!schema'  = './app.schema.psd1'

    Server = @{ Host = 'example.local' }

    Database = '!<shared::Database>'          # whole map from an included file
    DbUrl    = 'postgres://!<shared::Database.Url>/!<Service.Name | lower>'
    Metrics  = '!<monitoring::Endpoint>'

    BasePort = '!<base::Server.Port>'         # base's own value, before merging
    OwnHost  = '!<this::Server.Host>'         # this file's value
}
