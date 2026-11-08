# Walking a path through plain objects: maps, lists and objects with properties.

function Find-PsdKeyIn {
    param($Dict, [string] $Key, [bool] $CaseSensitive)
    foreach ($k in $Dict.PSBase.Keys) {
        if ($CaseSensitive) { if ([string]::Equals([string]$k, $Key, [System.StringComparison]::Ordinal)) { return @{ Found = $true; Key = $k } } }
        elseif ([string]::Equals([string]$k, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { return @{ Found = $true; Key = $k } }
    }
    @{ Found = $false; Key = $null }
}

function Get-PsdObjectKind {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) { return 'map' }
    if (Test-PsdList $Value) { return 'list' }
    if ($Value -is [string] -or $Value -is [bool] -or (Test-PsdNumber $Value) -or $Value -is [enum] -or $Value -is [datetime] -or $Value -is [guid] -or $Value -is [version]) { return 'scalar' }
    'object'
}

# One step down. Returns @{ Found; Value; Key; Code; Message }.
function Get-PsdObjectChild {
    param($Value, $Seg, [bool] $CaseSensitive, [string] $Under)
    $kind = Get-PsdObjectKind $Value
    $what = if ($Under) { $Under } else { 'the object' }
    switch ($kind) {
        'map' {
            if ($Seg.IsIndex) { return @{ Found = $false; Code = 'PSD308'; Message = "$what is a map, so [$($Seg.Index)] can't be used on it." } }
            $r = Find-PsdKeyIn $Value $Seg.Key $CaseSensitive
            if (-not $r.Found) {
                $m = if ($Under) { "'$($Seg.Key)' doesn't exist under $Under." } else { "'$($Seg.Key)' doesn't exist." }
                return @{ Found = $false; Code = 'PSD301'; Message = $m; Keys = $Value.PSBase.Keys }
            }
            return @{ Found = $true; Value = $Value[$r.Key]; Key = $r.Key }
        }
        'list' {
            if (-not $Seg.IsIndex) { return @{ Found = $false; Code = 'PSD308'; Message = "$what is a list, so .$($Seg.Key) can't be used on it. Use an index like [0]." } }
            $i = $Seg.Index
            if ($i -lt 0) { $i += $Value.Count }
            if ($i -lt 0 -or $i -ge $Value.Count) { return @{ Found = $false; Code = 'PSD307'; Message = "$what has $($Value.Count) items, so [$($Seg.Index)] doesn't exist." } }
            return @{ Found = $true; Value = $Value[$i]; Key = $i }
        }
        'object' {
            if ($Seg.IsIndex) { return @{ Found = $false; Code = 'PSD308'; Message = "$what isn't a list, so [$($Seg.Index)] can't be used on it." } }
            foreach ($p in $Value.PSObject.Properties) {
                $same = if ($CaseSensitive) { [string]::Equals($p.Name, $Seg.Key, [System.StringComparison]::Ordinal) } else { $p.Name -ieq $Seg.Key }
                if ($same) { return @{ Found = $true; Value = $p.Value; Key = $p.Name } }
            }
            $m = if ($Under) { "'$($Seg.Key)' doesn't exist under $Under." } else { "'$($Seg.Key)' doesn't exist." }
            return @{ Found = $false; Code = 'PSD301'; Message = $m; Keys = @($Value.PSObject.Properties | ForEach-Object Name) }
        }
        'null' { return @{ Found = $false; Code = 'PSD301'; Message = "$what is `$null, so nothing can be read from it." } }
    }
    @{ Found = $false; Code = 'PSD304'; Message = "$what is $(Get-PsdKindText $Value), so it has nothing inside it to read." }
}

function Find-PsdObjectPath {
    param($Object, $Segs, [bool] $CaseSensitive = $false)
    $cur = $Object
    for ($i = 0; $i -lt $Segs.Count; $i++) {
        $r = Get-PsdObjectChild $cur $Segs[$i] $CaseSensitive (Format-PsdSegs $Segs $i)
        if (-not $r.Found) { $r.At = $i; return $r }
        $cur = $r.Value
    }
    @{ Found = $true; Value = $cur }
}

function Set-PsdObjectChild {
    param($Container, $Key, $Value)
    $kind = Get-PsdObjectKind $Container
    if ($kind -eq 'map') { $Container[$Key] = $Value; return }
    if ($kind -eq 'list') { $Container[$Key] = $Value; return }
    $p = $Container.PSObject.Properties[[string]$Key]
    if ($p) { $p.Value = $Value } else { $Container | Add-Member -NotePropertyName ([string]$Key) -NotePropertyValue $Value }
}

# Sets a value, creating maps on the way. Returns $null or an error @{ Code; Message }.
function Set-PsdObjectPath {
    param($Object, $Segs, $Value)
    $cur = $Object
    for ($i = 0; $i -lt $Segs.Count; $i++) {
        $seg = $Segs[$i]
        $last = ($i -eq $Segs.Count - 1)
        $under = Format-PsdSegs $Segs $i
        $kind = Get-PsdObjectKind $cur
        if ($kind -eq 'map' -and -not $seg.IsIndex) {
            $r = Find-PsdKeyIn $cur $seg.Key $false
            $key = $seg.Key
            if ($r.Found) { $key = $r.Key }
            if ($last) { $cur[$key] = $Value; return $null }
            if (-not $r.Found -or $null -eq $cur[$key]) { $cur[$key] = [ordered]@{} }
            $cur = $cur[$key]
            continue
        }
        $r = Get-PsdObjectChild $cur $seg $false $under
        if (-not $r.Found) {
            if ($kind -eq 'object' -and $r.Code -eq 'PSD301') {
                if ($last) { Set-PsdObjectChild $cur $seg.Key $Value; return $null }
                $new = [ordered]@{}
                Set-PsdObjectChild $cur $seg.Key $new
                $cur = $new
                continue
            }
            return $r
        }
        if ($last) { Set-PsdObjectChild $cur $r.Key $Value; return $null }
        $cur = $r.Value
    }
    $null
}

# Removes a value. Lists that can't shrink are replaced by a shorter copy.
function Remove-PsdObjectPath {
    param($Object, $Segs)
    $parentSegs = New-PsdList
    for ($i = 0; $i -lt $Segs.Count - 1; $i++) { $parentSegs.Add($Segs[$i]) }
    $p = Find-PsdObjectPath $Object $parentSegs
    if (-not $p.Found) { return $p }
    $parent = $p.Value
    $seg = $Segs[$Segs.Count - 1]
    $r = Get-PsdObjectChild $parent $seg $false (Format-PsdSegs $parentSegs)
    if (-not $r.Found) { return $r }
    $kind = Get-PsdObjectKind $parent
    if ($kind -eq 'map') { $parent.Remove($r.Key); return $null }
    if ($kind -eq 'object') { $parent.PSObject.Properties.Remove($r.Key); return $null }
    if (-not $parent.IsFixedSize) { $parent.RemoveAt($r.Key); return $null }
    $items = New-PsdList
    for ($i = 0; $i -lt $parent.Count; $i++) { if ($i -ne $r.Key) { $items.Add($parent[$i]) } }
    if ($parentSegs.Count -eq 0) { return @{ Code = 'PSD308'; Message = "an item can't be removed from the top-level list itself." } }
    Set-PsdObjectPath $Object $parentSegs ($items.ToArray())
}

function Write-PsdPathError {
    param($Cmdlet, $R, [string] $Path)
    $ctx = New-PsdContext
    $hint = @()
    if ($R.ContainsKey('Keys') -and $R['Keys']) {
        $last = $Path
        $m = [regex]::Match($Path, '([^.\[\]"]+)"?$')
        if ($m.Success) { $last = $m.Groups[1].Value }
        $hint = @((Get-PsdDidYouMean $last $R['Keys']))
    }
    Add-PsdError $ctx $R.Code $R.Message -Key $Path -Hint $hint
    Write-PsdResult $Cmdlet $ctx $null
}
