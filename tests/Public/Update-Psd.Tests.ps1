BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Editing files' {
    It 'Update-Psd changes one value and keeps comments' {
        $dir = New-TestFiles @{ 'f.psd1' = "# top`n@{`n    # port`n    Port = 1   # inline`n    Server = @{`n        Host = 'a'`n    }`n}`n" }
        $f = Join-Path $dir 'f.psd1'
        Update-Psd $f -Key Port -Value 2
        Update-Psd $f -Key 'Server.Debug' -Value $true
        $t = [IO.File]::ReadAllText($f)
        $t | Should -Be "# top`n@{`n    # port`n    Port = 2   # inline`n    Server = @{`n        Host = 'a'`n        Debug = `$true`n    }`n}`n"
    }
}
