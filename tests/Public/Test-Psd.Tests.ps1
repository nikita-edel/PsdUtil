BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Test-Psd' {
    It 'passes the everything example, with its schema' {
        Test-Psd (Join-Path $Examples 'everything/app.psd1') | Should -BeTrue
    }

    It 'returns $false for a file with a problem, without writing an error' {
        $dir = New-TestFiles @{ 'bad.psd1' = "@{ A = '!<Nope>' }" }
        Test-Psd (Join-Path $dir 'bad.psd1') -ErrorAction Stop | Should -BeFalse
    }
}
