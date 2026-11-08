function Merge-Psd {
    <#
    .SYNOPSIS
    Merges files and maps in order. Later ones win.

    .DESCRIPTION
    Uses the same rules as '!merge': maps deep merge, everything else is replaced, and the merge
    operators (+=, =+, |=, -=, :=) work. A file brings its own chain and includes with it.
    References are worked out against the merged result.

    .PARAMETER InputObject
    Paths to files, or maps, in order.

    .PARAMETER Key
    Only these top-level keys are returned. Everything is still merged, so references work.

    .EXAMPLE
    Merge-Psd ./base.psd1, ./prod.psd1, @{ Tags = @('y') }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object[]] $InputObject,

        [string[]] $Key,

        [ValidateSet('Error', 'Warn', 'Null', 'Keep')]
        [string] $UnresolvedReference = 'Error',

        [System.Collections.IDictionary] $Limits
    )
    $ctx = New-PsdContext -Limits $Limits -Unresolved $UnresolvedReference
    $layers = New-PsdList
    $entry = $null
    $n = 0
    foreach ($item in $InputObject) {
        $n++
        if ($item -is [string] -or $item -is [IO.FileInfo]) {
            $f = Read-PsdFile (Resolve-PsdUserPath ([string]$item)) $ctx
            if ($null -eq $f -or $null -eq $f.Root) { continue }
            foreach ($l in (Get-PsdLayers $f $ctx)) { $layers.Add($l) }
            $entry = $f
        }
        elseif ($item -is [System.Collections.IDictionary] -or $item -is [System.Management.Automation.PSCustomObject]) {
            $sf = New-PsdSyntheticFile "input $n" $null
            $sf.Root = ConvertFrom-PsdObject $item $sf $ctx ''
            $layers.Add(@{ File = $sf; Only = $null; Root = $null })
        }
        else { Add-PsdError $ctx 'PSD206' "input $n is $(Get-PsdKindText $item). Merge-Psd takes paths and maps." }
    }
    if ($Key) {
        $have = New-PsdList
        foreach ($l in $layers) { foreach ($x in (Get-PsdTopKeys $l.File.Root)) { $have.Add($x) } }
        foreach ($k in $Key) {
            $hit = $false
            foreach ($h in $have) { if ($h -ieq $k) { $hit = $true } }
            if (-not $hit) { Add-PsdError $ctx 'PSD207' "'$k' isn't a key in any of the inputs." -Hint @((Get-PsdDidYouMean $k $have)) }
        }
    }
    if ($null -eq $entry) { $entry = New-PsdSyntheticFile 'merge' $null; $entry.Root = New-PsdMapNode $entry $null '' }
    $value = $null
    if ($layers.Count -gt 0 -and $ctx.Errors.Count -eq 0) {
        $doc = New-PsdDoc $entry $layers $ctx
        if ($Key) {
            # Everything is merged, so references still work. Only these keys are returned.
            $value = [ordered]@{}
            foreach ($k in $Key) {
                foreach ($have in $doc.Tree.V.PSBase.Keys) {
                    if ($have -ieq $k) { $value[$have] = Get-PsdNodeValue $doc.Tree.V[$have] $doc }
                }
            }
        }
        else { $value = Resolve-PsdDoc $doc }
    }
    Write-PsdResult $PSCmdlet $ctx 'the inputs'
    if ($ctx.Errors.Count -eq 0 -and $null -ne $value) { ConvertTo-PsdOutput $value }
}
