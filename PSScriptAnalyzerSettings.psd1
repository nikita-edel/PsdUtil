@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Internal helpers return values through ',' to keep lists intact; the output type is documented per command.
        'PSUseOutputTypeCorrectly'
        # Plural nouns like Get-PsdLayers and Resolve-PsdPaths are private helpers, not commands.
        'PSUseSingularNouns'
        # Private New-* helpers only build objects in memory. Public commands that write files support -WhatIf.
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.2')
        }
    }
}
