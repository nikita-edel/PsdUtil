# Applies after 10-first.psd1.
@{
    'Plugins |=' = @('core', 'cache')               # core is already there, only cache is added
    Server       = @{ Port = 9000 }                 # maps deep merge, the rest of Server stays
}
