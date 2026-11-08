@{
    RootModule           = 'PsdUtil.psm1'
    ModuleVersion        = '0.1.0'
    CompatiblePSEditions = @('Desktop', 'Core')
    GUID                 = '3b6f0f5e-2a51-4c1e-9d0b-6c2f8a7e4d19'
    Author               = 'Nikita Edel'
    CompanyName          = 'Nikita Edel'
    Copyright            = '(c) 2026 Nikita Edel. Licensed under the MIT License.'
    Description          = 'Reads, writes, merges and checks PowerShell data files (.psd1), with references, includes, conditions and schemas. Never runs code from a data file.'
    PowerShellVersion    = '5.1'

    # One entry per file in Public/. tests/Module.Tests.ps1 checks that the two stay in sync.
    FunctionsToExport    = @(
        'Add-PsdDefault'
        'Assert-PsdKey'
        'Compare-Psd'
        'ConvertFrom-Psd'
        'ConvertTo-Psd'
        'Export-Psd'
        'Format-Psd'
        'Get-PsdError'
        'Get-PsdMissingKey'
        'Get-PsdProvenance'
        'Get-PsdValue'
        'Import-Psd'
        'Merge-Psd'
        'New-PsdSchema'
        'New-PsdType'
        'Remove-PsdValue'
        'Resolve-PsdReference'
        'Set-PsdValue'
        'Test-Psd'
        'Test-PsdKey'
        'Test-PsdSchema'
        'Update-Psd'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('psd1', 'config', 'configuration', 'data', 'schema', 'merge', 'Windows', 'Linux', 'MacOS', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/nikita-edel/PsdUtil'
            ReleaseNotes = 'See CHANGELOG.txt'
        }
    }
}
