function Get-PsdValue {
    <#
    .SYNOPSIS
    Reads a value by path, like 'Server.Tls.Port', 'Plugins[-1]' or '"my.key".Sub'.

    .EXAMPLE
    Get-PsdValue $config -Path 'Server.Port'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path
    )
    process {
        $r = Find-PsdObjectPath $InputObject (ConvertFrom-PsdPathText $Path)
        if ($r.Found) { , $r.Value } else { Write-PsdPathError $PSCmdlet $r $Path }
    }
}
