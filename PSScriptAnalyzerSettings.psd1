@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        'PSUseSingularNouns'

        'PSAvoidGlobalVars'

        'PSAvoidGlobalAliases'

        'PSAvoidUsingWriteHost'

        # Internal helpers return values through ',' to keep lists intact.
        'PSUseOutputTypeCorrectly'

        # Private New-* helpers only build objects in memory. Public commands that write files support -WhatIf.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules        = @{
        PSUseCompatibleSyntax  = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }

        PSUseCompatibleCmdlets = @{
            Compatibility = @(
                'desktop-5.1.14393.206-windows'
                'core-6.1.0-windows'
                'core-6.1.0-linux'
                'core-6.1.0-macos'
            )
        }
    }
}
