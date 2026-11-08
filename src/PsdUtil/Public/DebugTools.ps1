function Compare-Psd {
    <#
    .SYNOPSIS
    Shows what was added, removed or changed between two files or objects.

    .DESCRIPTION
    Files are loaded with Import-Psd first. Lists are compared item by item.

    .EXAMPLE
    Compare-Psd ./base.psd1 ./next.psd1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $Left,

        [Parameter(Mandatory, Position = 1)]
        [object] $Right
    )
    $sides = New-PsdList
    foreach ($x in @($Left, $Right)) {
        if ($x -is [string] -or $x -is [IO.FileInfo]) {
            $r = Invoke-PsdLoad -Path ([string]$x)
            if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx ([string]$x); return }
            $sides.Add($r.Value)
        }
        else { $sides.Add($x) }
    }
    $out = New-PsdList
    Compare-PsdObjects $sides[0] $sides[1] '' $out
    foreach ($d in $out) { $d }
}

function Get-PsdProvenance {
    <#
    .SYNOPSIS
    Shows which file and line each value came from, and what it overrode.

    .EXAMPLE
    Get-PsdProvenance ./last.psd1 -Key 'Server.Port'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Position = 1)]
        [string[]] $Key,

        [System.Collections.IDictionary] $Override
    )
    $r = Invoke-PsdLoad -Path $Path -Override $Override -Prov
    if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx ([IO.Path]::GetFileName($Path)); return }
    foreach ($row in (Get-PsdProvenanceRows $r.Doc $r.Value $Key)) { $row }
}

function Resolve-PsdReference {
    <#
    .SYNOPSIS
    Shows how one value is worked out, step by step.

    .EXAMPLE
    Resolve-PsdReference ./last.psd1 -Key 'Service.Title'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, Position = 1)]
        [string] $Key,

        [System.Collections.IDictionary] $Override
    )
    $ctx = New-PsdContext
    $entry = Read-PsdFile (Resolve-PsdUserPath $Path) $ctx
    if ($null -eq $entry -or $null -eq $entry.Root) { Write-PsdResult $PSCmdlet $ctx ([IO.Path]::GetFileName($Path)); return }
    $doc = New-PsdFileDoc $entry $ctx $Override
    $segs = ConvertFrom-PsdPathText $Key
    $node = $doc.Tree
    foreach ($s in $segs) {
        if ($node.K -eq 'M' -and -not $s.IsIndex -and $node.V.Contains($s.Key)) { $node = $node.V[$s.Key] }
        elseif ($node.K -eq 'L' -and $s.IsIndex -and $s.Index -lt $node.V.Count) { $node = $node.V[$s.Index] }
        else {
            Add-PsdError $ctx 'PSD301' "'$Key' doesn't exist in $([IO.Path]::GetFileName($Path))."
            Write-PsdResult $PSCmdlet $ctx $null
            return
        }
    }
    $ctx.Trace = New-PsdList
    $value = Get-PsdNodeValue $node $doc
    Write-PsdResult $PSCmdlet $ctx $null
    $min = [int]::MaxValue
    foreach ($t in $ctx.Trace) { if ($t.Depth -lt $min) { $min = $t.Depth } }
    foreach ($t in $ctx.Trace) {
        $label = $t.Step
        if (-not $label) { $label = '(value)' }
        [pscustomobject]@{
            PSTypeName = 'PsdUtil.TraceStep'
            Step       = ('  ' * [Math]::Max(0, $t.Depth - $min)) + $label
            Expression = $t.Text
            Value      = Format-PsdTraceValue $t.Value
        }
    }
    [pscustomobject]@{ PSTypeName = 'PsdUtil.TraceStep'; Step = 'result'; Expression = $null; Value = Format-PsdTraceValue (ConvertTo-PsdOutput $value) }
}
