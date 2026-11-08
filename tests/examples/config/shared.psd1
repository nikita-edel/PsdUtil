# Included by last.psd1: nothing is merged, keys are read through shared::
@{
    Database = @{
        Host  = 'db.internal'
        Port  = 5432
        Url   = '!<Database.Host>:!<Database.Port>'
        Owner = '!<@name>'                    # an included file is its own document: 'shared'
    }
}
