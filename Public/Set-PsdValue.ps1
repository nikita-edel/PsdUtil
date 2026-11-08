function Set-PsdValue {
    <#
    .SYNOPSIS
    Changes a value in a loaded object by path. Missing maps on the way are created.

    .DESCRIPTION
    Only changes the object in memory. To change a file, use Update-Psd.

    .EXAMPLE
    Set-PsdValue $config -Path 'Server.Port' -Value 9100
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(Mandatory, Position = 2)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object] $Value,

        [switch] $PassThru
    )
    if (-not $PSCmdlet.ShouldProcess($Path, 'Set value')) { return }
    $err = Set-PsdObjectPath $InputObject (ConvertFrom-PsdPathText $Path) $Value
    if ($err) { Write-PsdPathError $PSCmdlet $err $Path; return }
    if ($PassThru) { $InputObject }
}
