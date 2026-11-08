# Shared by Test-PsdKey, Get-PsdMissingKey and Assert-PsdKey.

function Get-PsdKeyReport {
    param($Object, [string[]] $Key, [bool] $Exact, [bool] $CaseSensitive)
    $missing = New-PsdList
    $found = New-PsdList
    $extra = New-PsdList
    $byParent = [ordered]@{}
    foreach ($k in $Key) {
        $segs = ConvertFrom-PsdPathText $k
        $r = Find-PsdObjectPath $Object $segs $CaseSensitive
        if ($r.Found) { $found.Add($k) } else { $missing.Add($k) }
        $parent = $segs.GetRange(0, $segs.Count - 1)
        $pk = Format-PsdSegs $parent
        if (-not $byParent.Contains($pk)) { $byParent[$pk] = @{ Segs = $parent; Children = (New-PsdList) } }
        $last = $segs[$segs.Count - 1]
        if (-not $last.IsIndex) { $byParent[$pk].Children.Add($last.Key) }
    }
    if ($Exact) {
        foreach ($pk in $byParent.PSBase.Keys) {
            $p = Find-PsdObjectPath $Object $byParent[$pk].Segs $CaseSensitive
            if (-not $p.Found) { continue }
            $names = New-PsdList
            $kind = Get-PsdObjectKind $p.Value
            if ($kind -eq 'map') { foreach ($x in $p.Value.PSBase.Keys) { $names.Add([string]$x) } }
            elseif ($kind -eq 'object') { foreach ($x in $p.Value.PSObject.Properties) { $names.Add($x.Name) } }
            foreach ($n in $names) {
                $listed = $false
                foreach ($c in $byParent[$pk].Children) { if (Test-PsdKeySame $c $n $CaseSensitive) { $listed = $true } }
                if (-not $listed) { $extra.Add((Join-PsdPath $pk $n)) }
            }
        }
    }
    @{ Missing = $missing; Found = $found; Extra = $extra }
}
