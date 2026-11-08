# Applies layers on top of each other. Maps deep merge, everything else is replaced.
# List operators are recorded as 'O' nodes and run when the key is resolved.

function Merge-PsdMap {
    param($Base, $Layer, $M, [string] $Path)
    $out = New-PsdMapNode $Layer.File $null $Path
    Copy-PsdLocation $Layer $out
    if ($null -ne $Base) { foreach ($k in @($Base.V.PSBase.Keys)) { $out.V[$k] = $Base.V[$k] } }

    foreach ($k in @($Layer.V.PSBase.Keys)) {
        $v = $Layer.V[$k]
        $cp = Join-PsdPath $Path $k
        $prev = $null
        if ($out.V.Contains($k)) { $prev = $out.V[$k] }
        if ($v.K -eq 'M') {
            $nb = $null
            if ($null -ne $prev -and $prev.K -eq 'M') { $nb = $prev }
            $nv = Merge-PsdMap $nb $v $M $cp
        }
        else { $nv = ConvertTo-PsdNormal $v $M $cp }
        Set-PsdProv $M $cp $nv $prev
        $out.V[$k] = $nv
    }
    foreach ($op in $Layer.Ops) { Invoke-PsdMergeOp $out $op $M }
    foreach ($if in $Layer.Ifs) {
        if (Test-PsdIfTrue $if $M) { $out = Merge-PsdMap $out $if.Body $M $Path }
    }
    $out
}

# Applies the operators and conditions inside a value that isn't merged onto anything.
function ConvertTo-PsdNormal {
    param($Node, $M, [string] $Path)
    if ($Node.K -eq 'M') { return (Merge-PsdMap $null $Node $M $Path) }
    if ($Node.K -ne 'L') { return $Node }
    $needs = $false
    foreach ($x in $Node.V) { if ($x.K -eq 'M' -or $x.K -eq 'L') { $needs = $true; break } }
    if (-not $needs) { return $Node }
    $items = New-PsdList
    $i = 0
    foreach ($x in $Node.V) { $items.Add((ConvertTo-PsdNormal $x $M (Join-PsdPath $Path $i))); $i++ }
    $n = New-PsdNode 'L' $items $Node.File $null $Path
    Copy-PsdLocation $Node $n
    $n
}

function Set-PsdProv {
    param($M, [string] $Path, $New, $Prev)
    if ($null -eq $M.Prov) { return }
    $over = New-PsdList
    if ($null -ne $Prev) {
        $over.Add($Prev)
        if ($M.Prov.ContainsKey($Path)) { foreach ($x in $M.Prov[$Path].Over) { if ($x.Id -ne $Prev.Id) { $over.Add($x) } } }
    }
    $M.Prov[$Path] = @{ Node = $New; Over = $over }
}

function Add-PsdMergeError {
    param($M, [string] $Code, [string] $Message, $Op, [string[]] $Hint = @())
    if ($M.Quiet) { return }
    Add-PsdError $M.Ctx $Code $Message -File $Op.File -Line $Op.Line -Column $Op.Col -Length $Op.Len -Key $Op.Path -Hint $Hint
}

function New-PsdOpNode {
    param($Base, $Op, $Arg)
    $n = New-PsdNode 'O' $null $Op.File $null $Op.Path
    $n.Line = $Op.Line; $n.Col = $Op.Col; $n.Text = $Op.Text
    $n.KeyLine = $Op.Line; $n.KeyCol = $Op.Col; $n.KeyLen = $Op.Len
    $n.Base = $Base
    $n.Op = $Op.Op
    $n.Arg = $Arg
    $n
}

function Get-PsdNodeKindText {
    param($Node)
    switch ($Node.K) {
        'M' { return 'a map' }
        'L' { return 'a list' }
        'S' { return (Get-PsdKindText $Node.V) }
        default { return 'a reference' }
    }
}

function Invoke-PsdMergeOp {
    param($Out, $Op, $M)
    $k = $Op.Key
    $has = $Out.V.Contains($k)
    $prev = $null
    if ($has) { $prev = $Out.V[$k] }
    $arg = ConvertTo-PsdNormal $Op.Arg $M $Op.Path
    $shown = Format-PsdKeyText $k

    switch ($Op.Op) {
        '-=' {
            if ($arg.K -eq 'S' -and $arg.V -is [bool] -and $arg.V) {
                if ($has) {
                    $Out.V.Remove($k)
                    if ($M.Prov) { [void]$M.Prov.Remove($Op.Path) }
                }
                else { Add-PsdMergeError $M 'PSD212' "$shown can't be deleted, because it doesn't exist." $Op @((Get-PsdDidYouMean $k $Out.V.PSBase.Keys)) }
                return
            }
            if ($arg.K -eq 'S' -and ($null -eq $arg.V -or $arg.V -is [bool])) {
                Add-PsdMergeError $M 'PSD211' "'$shown -=' needs `$true to delete the key, or a list of items to remove." $Op @("Delete it: '$k -=' = `$true. Remove items: '$k -=' = @('a', 'b').")
                return
            }
            if ($arg.K -eq 'M') {
                Add-PsdMergeError $M 'PSD211' "'$shown -=' can't take a map. Give it `$true to delete the key, or a list of items or keys to remove." $Op
                return
            }
            if (-not $has) {
                Add-PsdMergeError $M 'PSD212' "nothing can be removed from $shown, because it doesn't exist." $Op @((Get-PsdDidYouMean $k $Out.V.PSBase.Keys))
                return
            }
            if ($prev.K -eq 'M') {
                $names = Get-PsdItems $arg
                if ($arg.K -eq 'L') { $names = Get-PsdItems $arg.V }
                $copy = New-PsdMapNode $prev.File $null $prev.Path
                Copy-PsdLocation $prev $copy
                foreach ($x in $prev.V.PSBase.Keys) { $copy.V[$x] = $prev.V[$x] }
                foreach ($n in $names) {
                    if ($n.K -ne 'S' -or $n.V -isnot [string]) {
                        Add-PsdMergeError $M 'PSD211' "removing from the map $shown needs key names." $Op
                        continue
                    }
                    if ($copy.V.Contains($n.V)) {
                        $copy.V.Remove($n.V)
                        if ($M.Prov) { [void]$M.Prov.Remove((Join-PsdPath $Op.Path $n.V)) }
                    }
                    else { Add-PsdMergeError $M 'PSD212' "'$($n.V)' isn't a key of $shown, so it can't be removed." $Op @((Get-PsdDidYouMean $n.V $prev.V.PSBase.Keys)) }
                }
                $Out.V[$k] = $copy
                return
            }
            if ($prev.K -eq 'S' -and $null -ne $prev.V) {
                Add-PsdMergeError $M 'PSD210' "-= only works on lists and maps, but $shown is $(Get-PsdNodeKindText $prev)." $Op
                return
            }
            $Out.V[$k] = New-PsdOpNode $prev $Op $arg
            Set-PsdProv $M $Op.Path $Out.V[$k] $prev
        }
        ':=' {
            $Out.V[$k] = $arg
            Set-PsdProv $M $Op.Path $arg $prev
        }
        default {
            $base = $prev
            if ($null -ne $base -and $base.K -eq 'S' -and $null -eq $base.V) { $base = $null }
            if ($null -ne $base -and $base.K -eq 'M') {
                Add-PsdMergeError $M 'PSD210' "$($Op.Op) only works on lists, but $shown is a map." $Op @("To add keys to a map, write them: $k = @{ NewKey = ... }")
                return
            }
            if ($null -ne $base -and $base.K -eq 'S') {
                Add-PsdMergeError $M 'PSD210' "$($Op.Op) only works on lists, but $shown is $(Get-PsdNodeKindText $base)." $Op
                return
            }
            $Out.V[$k] = New-PsdOpNode $base $Op $arg
            Set-PsdProv $M $Op.Path $Out.V[$k] $prev
        }
    }
}

function Test-PsdIfTrue {
    param($If, $M)
    switch ($M.Mode) {
        'None' { return $false }
        'All' { return $true }
    }
    $doc = $M.Doc
    if ($doc.Decisions.ContainsKey($If.Id)) { return $doc.Decisions[$If.Id] }
    $doc.Decisions[$If.Id] = $false
    $ev = @{ Doc = $doc.Prelim; Node = $If; InCond = $true; Final = $doc }
    $r = Test-PsdCondition $If.Cond $ev
    $doc.Decisions[$If.Id] = $r
    $r
}
