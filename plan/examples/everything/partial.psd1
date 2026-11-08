# app.psd1 only takes Logging and Cache from this file.
@{
    Logging = @{
        Level = 'Info'
        File  = '!<Builtins.Dir>/!<@name>.log'
    }

    Cache = @{ Size = 10 }

    Ignored = 'not in the result'
}
