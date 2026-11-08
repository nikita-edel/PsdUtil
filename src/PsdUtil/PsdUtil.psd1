@{
    RootModule           = 'PsdUtil.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '3b6f0f5e-2a51-4c1e-9d0b-6c2f8a7e4d19'
    Author               = 'Nikita Edel'
    Copyright            = '(c) Nikita Edel. All rights reserved.'
    Description          = 'Reads, writes, merges and checks PowerShell data files (.psd1), with references, includes, conditions and schemas. Never runs code from a data file.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Import-Psd', 'ConvertFrom-Psd', 'ConvertTo-Psd', 'Export-Psd', 'Merge-Psd',
        'Test-Psd', 'Get-PsdError', 'Test-PsdSchema', 'Test-PsdKey', 'Get-PsdMissingKey', 'Assert-PsdKey',
        'Get-PsdValue', 'Set-PsdValue', 'Remove-PsdValue', 'Update-Psd', 'Format-Psd',
        'Add-PsdDefault', 'New-PsdSchema', 'New-PsdType',
        'Compare-Psd', 'Resolve-PsdReference', 'Get-PsdProvenance'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('psd1', 'config', 'configuration', 'data', 'schema', 'merge')
            ProjectUri = 'https://github.com/nikita-edel/PsdUtil'
        }
    }
}
