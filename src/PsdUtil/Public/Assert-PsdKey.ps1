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
