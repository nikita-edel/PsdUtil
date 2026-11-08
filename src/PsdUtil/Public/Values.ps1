function Write-PsdPathError {
    param($Cmdlet, $R, [string] $Path)
    $ctx = New-PsdContext
    $hint = @()
    if ($R.ContainsKey('Keys') -and $R['Keys']) {
        $last = $Path
        $m = [regex]::Match($Path, '([^.\[\]"]+)"?$')
        if ($m.Success) { $last = $m.Groups[1].Value }
        $hint = @((Get-PsdDidYouMean $last $R['Keys']))
    }
    Add-PsdError $ctx $R.Code $R.Message -Key $Path -Hint $hint
    Write-PsdResult $Cmdlet $ctx $null
}

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
