function Compare-Psd {
    <#
    .SYNOPSIS
    Shows what was added, removed or changed between two files or objects.

    .DESCRIPTION
    Files are loaded with Import-Psd first. Lists are compared item by item.

    .EXAMPLE
    Compare-Psd ./base.psd1 ./next.psd1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $Left,

        [Parameter(Mandatory, Position = 1)]
        [object] $Right
    )
    $sides = New-PsdList
    foreach ($x in @($Left, $Right)) {
        if ($x -is [string] -or $x -is [IO.FileInfo]) {
            $r = Invoke-PsdLoad -Path ([string]$x)
            if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx ([string]$x); return }
            $sides.Add($r.Value)
        }
        else { $sides.Add($x) }
    }
    $out = New-PsdList
    Compare-PsdObjects $sides[0] $sides[1] '' $out
    foreach ($d in $out) { $d }
}
