# last.psd1 merges only Logging from here.
@{
    Logging = @{
        Level = 'Info'
        File  = '!<Paths.Logs>/!<@name>.log'  # merged, so it resolves against the final result
    }

    NotMerged = 'not in the result'
}
