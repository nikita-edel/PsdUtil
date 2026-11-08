function Update-Psd {
    <#
    .SYNOPSIS
    Changes one value in a .psd1 file. Comments and formatting stay.

    .DESCRIPTION
    Only the text of that value is replaced. A new key is added before the closing } with the
    indentation of its neighbours. Only this file is changed, chains aren't followed.

    .EXAMPLE
    Update-Psd ./next.psd1 -Key 'Server.Port' -Value 9100
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, Position = 1)]
        [string] $Key,

        [Parameter(Mandatory, Position = 2)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object] $Value,

        [System.Collections.IDictionary] $Format
    )
    $ctx = New-PsdContext
    $f = Get-PsdFormat $Format $ctx
    $full = Resolve-PsdUserPath $Path
    $segs = ConvertFrom-PsdPathText $Key
    if ($ctx.Errors.Count -eq 0 -and $PSCmdlet.ShouldProcess($full, "Set $Key")) {
        $null = Update-PsdFileValue $full $segs $Value $f $ctx
    }
    Write-PsdResult $PSCmdlet $ctx $null
}
