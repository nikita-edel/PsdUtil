# Middle of the chain. Shows the merge operators.
@{
    '!merge' = './base.psd1'

    Server = @{ Port = 9000 }                 # maps deep merge by default, Host is kept
    Tags   = @('x')                           # arrays replace by default

    'Plugins +='        = @('cache')          # add to the earlier list
    'Legacy :='         = @{ C = 3 }          # replace the map instead of merging
    'Deprecated -='     = $true               # delete the key
    'Features -='       = @('beta')           # delete an item
}
