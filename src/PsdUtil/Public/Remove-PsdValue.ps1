function Remove-PsdValue {
    <#
    .SYNOPSIS
    Removes a key or a list item from a loaded object by path.

    .EXAMPLE
    Remove-PsdValue $config -Path 'Token'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [switch] $PassThru
    )
    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove value')) { return }
    $segs = ConvertFrom-PsdPathText $Path
    $err = Remove-PsdObjectPath $InputObject $segs
    if ($err) { Write-PsdPathError $PSCmdlet $err $Path; return }
    if ($PassThru) { $InputObject }
}
