BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Get-PsdError' {
    It 'returns nothing for the everything example' {
        @(Get-PsdError (Join-Path $Examples 'everything/app.psd1')).Count | Should -Be 0
    }

    It 'returns the problems as objects' {
        $dir = New-TestFiles @{ 'bad.psd1' = "@{`n    A = '!<Nope>'`n}" }
        $e = @(Get-PsdError (Join-Path $dir 'bad.psd1'))
        $e.Count | Should -Be 1
        $e[0].Code | Should -Be 'PSD301'
        $e[0].Line | Should -Be 2
    }

    It 'checks an object in memory against a schema' {
        $dir = New-TestFiles @{ 's.psd1' = "@{ Properties = @{ A = 'int' } }" }
        (Get-PsdError -InputObject @{ A = 'x' } -Schema (Join-Path $dir 's.psd1')).Code | Should -Be 'PSD501'
    }
}
