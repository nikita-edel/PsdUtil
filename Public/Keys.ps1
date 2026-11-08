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

function Assert-PsdKey {
    <#
    .SYNOPSIS
    Throws one error that lists every missing key.

    .EXAMPLE
    Assert-PsdKey $config -Key Stage, 'Server.Port'
    #>
    [CmdletBinding()]
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
        if ($r.Missing.Count -eq 0 -and $r.Extra.Count -eq 0) { return }
        $lines = New-PsdList
        if ($r.Missing.Count -gt 0) { $lines.Add("These keys are missing: $($r.Missing -join ', ').") }
        if ($r.Extra.Count -gt 0) { $lines.Add("These keys shouldn't be there: $($r.Extra -join ', ').") }
        $ex = New-Object System.Exception ($lines -join ' ')
        $rec = New-Object System.Management.Automation.ErrorRecord $ex, 'PSD301', ([System.Management.Automation.ErrorCategory]::InvalidData), $InputObject
        $PSCmdlet.ThrowTerminatingError($rec)
    }
}
