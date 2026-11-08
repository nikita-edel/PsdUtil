# A reusable piece of schema, included by app.schema.psd1.
@{
    Database = @{
        Type       = 'map'
        Properties = @{
            Host   = @{ Type = 'string'; Required = $true }
            Port   = 'int'
            Url    = 'string'
            Owner  = 'string'
            Driver = 'string'
        }
    }
}
