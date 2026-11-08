function Get-PsdProvenance {
    <#
    .SYNOPSIS
    Shows which file and line each value came from, and what it overrode.

    .PARAMETER Include
    Maps from the caller, by name, read with !<name::Key>. See Import-Psd.

    .EXAMPLE
    Get-PsdProvenance ./last.psd1 -Key 'Server.Port'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Position = 1)]
        [string[]] $Key,

        [object] $Override,

        [System.Collections.IDictionary] $Include
    )
    $r = Invoke-PsdLoad -Path $Path -Override $Override -Include $Include -Prov
    if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx ([IO.Path]::GetFileName($Path)); return }
    foreach ($row in (Get-PsdProvenanceRows $r.Doc $r.Value $Key)) { $row }
}
