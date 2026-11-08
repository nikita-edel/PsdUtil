function Merge-Psd {
    <#
    .SYNOPSIS
    Merges files and maps in order. Later ones win.

    .DESCRIPTION
    Uses the same rules as '!merge': maps deep merge, everything else is replaced, and the merge
    operators (+=, =+, |=, -=, :=) work. A file brings its own chain and includes with it.
    References are worked out against the merged result.

    .PARAMETER InputObject
    Paths to files, or maps, in order. A generated class works too, if it was made from a map.
    A map can have '!name' = 'team', to read it as !<team::Key> and to name it in errors.

    .PARAMETER Key
    Only these top-level keys are returned. Everything is still merged, so references work.

    .PARAMETER Schema
    Checks the merged result, with the same messages as Import-Psd.

    .PARAMETER Include
    Maps from the caller, by name. They work like '!include': read them with !<name::Key>.
    Their keys aren't in the result and the schema doesn't check them.

    .EXAMPLE
    Merge-Psd ./base.psd1, ./prod.psd1, @{ Tags = @('y') }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object[]] $InputObject,

        [string[]] $Key,

        [string] $Schema,

        [System.Collections.IDictionary] $Include,

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
        elseif ($item -is [System.Collections.IDictionary] -or $item -is [System.Management.Automation.PSCustomObject] -or $null -ne (Get-PsdKeptMap $item)) {
            $sf = New-PsdSyntheticFile "input $n" $null
            $sf.Root = ConvertFrom-PsdObject $item $sf $ctx '' -AllowName
            $layers.Add(@{ File = $sf; Only = $null; Root = $null })
            if ($sf.Named) { $entry = $sf }
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
        $doc = New-PsdDoc $entry $layers $ctx $false $Include
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
        if ($Schema -and $ctx.Errors.Count -eq 0) {
            $whole = Resolve-PsdDoc $doc
            if ($ctx.Errors.Count -eq 0) { Test-PsdDocSchema $whole $doc (Resolve-PsdUserPath $Schema) $null $ctx }
        }
    }
    Write-PsdResult $PSCmdlet $ctx 'the inputs'
    if ($ctx.Errors.Count -eq 0 -and $null -ne $value) { ConvertTo-PsdOutput $value }
}
