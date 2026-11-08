function Get-PsdMissingKey {
    <#
    .SYNOPSIS
    Returns the keys that don't exist. With -Exact, also the keys that shouldn't be there.

    .EXAMPLE
    Get-PsdMissingKey $config -Key Stage, Nope
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string[]] $Key,

        [switch] $Exact,

        [switch] $CaseSensitive
    )
    process {
        $r = Get-PsdKeyReport $InputObject $Key $Exact.IsPresent $CaseSensitive.IsPresent
        foreach ($m in $r.Missing) { $m }
        foreach ($x in $r.Extra) { $x }
    }
}
