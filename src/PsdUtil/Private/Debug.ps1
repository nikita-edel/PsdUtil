# Comparing, provenance and reference tracing.

function Test-PsdSame {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
    if ($A -is [string] -and $B -is [string]) { return [string]::Equals($A, $B, [System.StringComparison]::Ordinal) }
    if ((Test-PsdNumber $A) -and (Test-PsdNumber $B)) { return ([double]$A -eq [double]$B) }
    if ($A.GetType() -ne $B.GetType()) { return $false }
    $A.Equals($B)
}

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
        param($change, $l, $r)
        $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = $shown; Change = $change; Left = $l; Right = $r })
    }
    if (($lk -eq 'map' -or $lk -eq 'object') -and ($rk -eq 'map' -or $rk -eq 'object')) {
        $lp = Get-PsdPairs $Left
        $rp = Get-PsdPairs $Right
        foreach ($k in $lp.PSBase.Keys) {
            $cp = Join-PsdPath $Path $k
            if (-not $rp.Contains($k)) { $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = $cp; Change = 'removed'; Left = $lp[$k]; Right = $null }) }
            else { Compare-PsdObjects $lp[$k] $rp[$k] $cp $Out }
        }
        foreach ($k in $rp.PSBase.Keys) {
            if (-not $lp.Contains($k)) { $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = (Join-PsdPath $Path $k); Change = 'added'; Left = $null; Right = $rp[$k] }) }
        }
        return
    }
    if ($lk -eq 'list' -and $rk -eq 'list') {
        $n = [Math]::Max($Left.Count, $Right.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $cp = Join-PsdPath $Path $i
            if ($i -ge $Right.Count) { $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = $cp; Change = 'removed'; Left = $Left[$i]; Right = $null }) }
            elseif ($i -ge $Left.Count) { $Out.Add([pscustomobject]@{ PSTypeName = 'PsdUtil.Difference'; Path = $cp; Change = 'added'; Left = $null; Right = $Right[$i] }) }
            else { Compare-PsdObjects $Left[$i] $Right[$i] $cp $Out }
        }
        return
    }
    if ($lk -ne $rk -or -not (Test-PsdSame $Left $Right)) { & $add 'changed' $Left $Right }
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
        $rec = $null
        foreach ($k in $Doc.Prov.PSBase.Keys) { if ($k -ieq $p) { $rec = $Doc.Prov[$k] } }
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
