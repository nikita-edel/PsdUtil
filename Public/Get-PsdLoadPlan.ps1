function Get-PsdLoadPlan {
    <#
    .SYNOPSIS
    Shows which files a load used, in merge order, and what it decided on the way.

    .DESCRIPTION
    Files holds the files in merge order, the last one wins. Steps holds every condition and every path with a
    reference, in the order they were decided: Round, Kind (If or Path), File, Line, Text, Result, and Reads with the
    keys it read and their values at that moment.

    .PARAMETER Include
    Maps from the caller, by name, read with !<name::Key>. See Import-Psd.

    .PARAMETER Loader
    Reads files that aren't .psd1, like .ps1 scripts. See Import-Psd.

    .EXAMPLE
    (Get-PsdLoadPlan ./app.psd1 -Include @{ run = @{ Stage = 'prod' } }).Steps | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [object] $Override,

        [System.Collections.IDictionary] $Include,

        [scriptblock] $Loader
    )
    $r = Invoke-PsdLoad -Path $Path -Override $Override -Include $Include -Loader $Loader
    if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx ([IO.Path]::GetFileName($Path)); return }
    Get-PsdPlanResult $r.Doc
}
