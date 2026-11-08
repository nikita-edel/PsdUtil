BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Debug commands' {
    It 'Resolve-PsdReference shows the steps' {
        $steps = @(Resolve-PsdReference (Join-Path $Examples 'config/last.psd1') -Key 'Service.Title')
        $steps[-1].Value | Should -Be 'LAST (dev)'
        ($steps | Where-Object { $_.Step.Trim() -eq '| upper' }).Value | Should -Be 'LAST'
    }
}
