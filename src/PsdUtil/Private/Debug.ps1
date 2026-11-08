# Comparing, provenance and reference tracing.

function Get-PsdPairs {
    param($Value)
    $pairs = [ordered]@{}
    if ($Value -is [System.Collections.IDictionary]) { foreach ($k in $Value.PSBase.Keys) { $pairs[[string]$k] = $Value[$k] } }
    else { foreach ($p in $Value.PSObject.Properties) { $pairs[$p.Name] = $p.Value } }
    $pairs
}

function Compare-PsdObjects {
    param($Left, $Right, [string] $Path, $Out)
    $lk = Get-PsdObjectKind $Left
    $rk = Get-PsdObjectKind $Right
    $shown = if ($Path) { $Path } else { '(top)' }
    $add = {
        param([string] $at, $change, $l, $r)
        $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = $at; Change = $change; Left = $l; Right = $r })
    }
    if ($lk -in 'map', 'object' -and $rk -in 'map', 'object') {
        $lp = Get-PsdPairs $Left
        $rp = Get-PsdPairs $Right
        foreach ($k in $lp.PSBase.Keys) {
            $cp = Join-PsdPath $Path $k
            if (-not $rp.Contains($k)) { & $add $cp 'removed' $lp[$k] $null }
            else { Compare-PsdObjects $lp[$k] $rp[$k] $cp $Out }
        }
        foreach ($k in $rp.PSBase.Keys) {
            if (-not $lp.Contains($k)) { & $add (Join-PsdPath $Path $k) 'added' $null $rp[$k] }
        }
        return
    }
    if ($lk -eq 'list' -and $rk -eq 'list') {
        $n = [Math]::Max($Left.Count, $Right.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $cp = Join-PsdPath $Path $i
            if ($i -ge $Right.Count) { & $add $cp 'removed' $Left[$i] $null }
            elseif ($i -ge $Left.Count) { & $add $cp 'added' $null $Right[$i] }
            else { Compare-PsdObjects $Left[$i] $Right[$i] $cp $Out }
        }
        return
    }
    if ($lk -ne $rk -or -not (Test-PsdEqual $Left $Right 'Ordinal')) { & $add $shown 'changed' $Left $Right }
}

function Get-PsdLocText {
    param($Node)
    if ($null -eq $Node -or $null -eq $Node.File) { return '' }
    $f = $Node.File
    if ($f.Synthetic) { return "<$($f.Name)>" }
    $t = $f.Name + $f.Ext
    $line = $Node.Line
    $col = $Node.Col
    if ($Node.KeyLine -gt 0 -and $Node.K -eq 'M') { $line = $Node.KeyLine; $col = $Node.KeyCol }
    if ($line -gt 0) { $t += ":${line}:$col" }
    $t
}

function Get-PsdProvenanceRows {
    param($Doc, $Value, $Keys)
    $rows = New-PsdList
    $paths = New-PsdList
    if ($Keys) {
        foreach ($k in $Keys) { $paths.Add((Format-PsdSegs (ConvertFrom-PsdPathText $k))) }
    }
    else {
        foreach ($p in $Doc.Prov.PSBase.Keys) { if ($Doc.Prov[$p].Node.K -ne 'M') { $paths.Add($p) } }
    }
    foreach ($p in $paths) {
        $rec = $Doc.Prov[$p]
        $v = $null
        $found = Find-PsdObjectPath $Value (ConvertFrom-PsdPathText $p)
        if ($found.Found) { $v = $found.Value }
        $over = New-PsdList
        $src = ''
        if ($rec) {
            $src = Get-PsdLocText $rec.Node
            foreach ($o in $rec.Over) { $over.Add((Get-PsdLocText $o)) }
        }
        elseif (-not $found.Found) { continue }
        $rows.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Provenance'; Key = $p; Value = $v; Source = $src; Overrides = ($over -join ', ') })
    }
    , $rows
}

function Format-PsdTraceValue {
    param($Value)
    if ($Value -is [string]) { return $Value }
    if (Test-PsdContainer $Value) { return (Get-PsdKindText $Value) }
    Format-PsdValueShort $Value
}
