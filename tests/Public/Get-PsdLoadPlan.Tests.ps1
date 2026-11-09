BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1')
}

Describe 'Get-PsdLoadPlan' {
    It 'lists the files in merge order and each decision with what it read' {
        $dir = New-TestFiles @{
            'a.psd1' = "@{ '!merge' = './base.psd1'; On = `$true; '!if !<On>' = @{ Mode = 'x'; '!merge +=' = './extra.psd1' }; '!if !<Mode> -eq `"x`"' = @{ Y = 1 }; '!if false' = @{ '!merge +=' = './no.psd1' } }"
            'base.psd1' = "@{ B = 1 }"
            'extra.psd1' = "@{ E = 1 }"
        }
        $plan = Get-PsdLoadPlan (Join-Path $dir 'a.psd1')
        @($plan.Files | ForEach-Object { Split-Path $_ -Leaf }) -join ',' | Should -Be 'base.psd1,extra.psd1,a.psd1'
        $steps = @($plan.Steps)
        $steps.Count | Should -Be 3
        $first = $steps | Where-Object { $_.Text -eq '!<On>' }
        $first.Round | Should -Be 1
        $first.Kind | Should -Be 'If'
        $first.Result | Should -BeTrue
        $first.Reads['on'] | Should -BeTrue
        $later = $steps | Where-Object { $_.Text -like '*Mode*' }
        $later.Round | Should -Be 2
        $later.Reads['mode'] | Should -Be 'x'
    }

    It 'lists paths with a reference' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ N = 'x'; '!merge' = './!<N>.psd1' }"; 'x.psd1' = "@{ K = 1 }" }
        $step = @((Get-PsdLoadPlan (Join-Path $dir 'a.psd1')).Steps)[0]
        $step.Kind | Should -Be 'Path'
        $step.Result | Should -Be './x.psd1'
    }

    It 'has no steps when nothing has to be decided' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ K = 1 }" }
        @((Get-PsdLoadPlan (Join-Path $dir 'a.psd1')).Steps).Count | Should -Be 0
    }

    It 'writes the errors of the load' {
        $dir = New-TestFiles @{ 'a.psd1' = "@{ K = '!<Nope>' }" }
        Get-ErrorCode { Get-PsdLoadPlan ./a.psd1 } $dir | Should -Contain 'PSD301'
    }
}
