function Test-PsdKey {
    <#
    .SYNOPSIS
    Checks that keys exist. Paths like 'Server.Port' and 'Plugins[0]' work.

    .PARAMETER Exact
    The maps that hold the keys may not have any other keys.

    .PARAMETER Any
    At least one of the keys has to exist.

    .PARAMETER CaseSensitive
    Key names have to match case too.

    .EXAMPLE
    Test-PsdKey $config -Key Stage, 'Server.Port'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string[]] $Key,

        [switch] $Exact,

        [switch] $Any,

        [switch] $CaseSensitive
    )
    process {
        $r = Get-PsdKeyReport $InputObject $Key $Exact.IsPresent $CaseSensitive.IsPresent
        if ($Any) { return ($r.Found.Count -gt 0) }
        ($r.Missing.Count -eq 0) -and ($r.Extra.Count -eq 0)
    }
}
