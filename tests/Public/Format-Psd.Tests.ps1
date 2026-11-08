BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Editing files' {
    It 'Format-Psd re-indents and keeps comments' {
        $dir = New-TestFiles @{ 'f.psd1' = "@{`n# c`n  A = 1`n      B = @{`n  C = 2   `n  }`n}" }
        $f = Join-Path $dir 'f.psd1'
        Format-Psd $f
        [IO.File]::ReadAllText($f) | Should -BeExactly "@{`n    # c`n    A = 1`n    B = @{`n        C = 2`n    }`n}"
    }
}
