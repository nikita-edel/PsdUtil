# Included by app.psd1. Nothing is merged, keys are read through shared::
@{
    '!include' = './vendor.psd1'                    # !include with one path

    Database = @{
        Host   = 'db.internal'
        Port   = 5432
        Url    = '!<Database.Host>:!<Database.Port>'
        Owner  = '!<@name>'                         # an included file is its own document
        Driver = '!<vendor::Driver>'
    }
}
