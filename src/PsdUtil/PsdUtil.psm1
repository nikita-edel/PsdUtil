Set-StrictMode -Version 3.0

foreach ($folder in 'Private', 'Public') {
    foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1') {
        . $file.FullName
    }
}

Export-ModuleMember -Function @(
    'Import-Psd', 'ConvertFrom-Psd', 'ConvertTo-Psd', 'Export-Psd', 'Merge-Psd',
    'Test-Psd', 'Get-PsdError', 'Test-PsdSchema', 'Test-PsdKey', 'Get-PsdMissingKey', 'Assert-PsdKey',
    'Get-PsdValue', 'Set-PsdValue', 'Remove-PsdValue', 'Update-Psd', 'Format-Psd',
    'Add-PsdDefault', 'New-PsdSchema', 'New-PsdType',
    'Compare-Psd', 'Resolve-PsdReference', 'Get-PsdProvenance'
)
