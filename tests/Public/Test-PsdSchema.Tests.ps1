BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Schema' {
    It 'checks enums from !types and .NET' {
        $dir = New-TestFiles @{ 'T.psm1' = 'enum Level { Debug; Info }'; 's.psd1' = "@{ '!types' = './T.psm1'; Properties = @{ L = '[Level]'; D = '[System.DayOfWeek]'; V = '[version]' } }" }
        Test-PsdSchema @{ L = 'info'; D = 'Monday'; V = '1.2' } -Schema (Join-Path $dir 's.psd1') | Should -BeTrue
        Test-PsdSchema @{ L = 'Loud' } -Schema (Join-Path $dir 's.psd1') | Should -BeFalse
        (Get-PsdError -InputObject @{ L = 'Loud' } -Schema (Join-Path $dir 's.psd1')).Code | Should -Be 'PSD504'
    }
}
