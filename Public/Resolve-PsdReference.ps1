function Resolve-PsdReference {
    <#
    .SYNOPSIS
    Shows how one value is worked out, step by step.

    .PARAMETER Include
    Maps from the caller, by name, read with !<name::Key>. See Import-Psd.

    .EXAMPLE
    Resolve-PsdReference ./last.psd1 -Key 'Service.Title'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, Position = 1)]
        [string] $Key,

        [object] $Override,

        [System.Collections.IDictionary] $Include
    )
    $ctx = New-PsdContext
    $entry = Read-PsdFile (Resolve-PsdUserPath $Path) $ctx
    if ($null -eq $entry -or $null -eq $entry.Root) { Write-PsdResult $PSCmdlet $ctx ([IO.Path]::GetFileName($Path)); return }
    $doc = New-PsdFileDoc $entry $ctx $Override -Include $Include
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
