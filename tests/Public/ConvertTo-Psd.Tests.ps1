BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Writing' {
    It 'round-trips' {
        $o = [ordered]@{ S = "it's !<x>"; I = 1; L = [long]5; D = 2.0; M = 1.5d; B = $true; N = $null; E = @(); One = @('x'); Nested = [ordered]@{ 'my.key' = @(1, [ordered]@{ A = 'b' }); '!bang' = 1 } }
        $back = ConvertFrom-Psd -Text (ConvertTo-Psd $o)
        Compare-TestValue $o $back | Should -BeNullOrEmpty
    }

    It 'writes dates, guids, versions, enums and objects' {
        $t = ConvertTo-Psd ([ordered]@{ D = [datetime]'2026-01-02T03:04:05'; G = [guid]'7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'; V = [version]'1.2.3'; E = [System.DayOfWeek]::Monday; O = [pscustomobject]@{ A = 1 } })
        $t | Should -Match "D = '2026-01-02T03:04:05.0000000'"
        $t | Should -Match "G = '7f1c2a54-0b6e-4e0a-9d3a-2c1b5e8f4a10'"
        $t | Should -Match "V = '1.2.3'"
        $t | Should -Match "E = 'Monday'"
        $t | Should -Match 'O = @\{'
    }

    It 'follows the format options' {
        $t = ConvertTo-Psd ([ordered]@{ Bb = 1; A = @(1, 2, 3); S = 'x' }) -Format @{ Indent = 2; SortKeys = $true; AlignEquals = $true; InlineArrayMax = 2; Quote = 'Double'; LineEnding = 'LF' }
        $t | Should -BeExactly "@{`n  A  = @(`n    1`n    2`n    3`n  )`n  Bb = 1`n  S  = `"x`"`n}"
    }
}
