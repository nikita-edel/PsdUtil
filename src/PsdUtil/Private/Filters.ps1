# The fixed list of filters. None of them can loop.

# name = number of arguments, kind of value it works on
$script:PsdFilters = [ordered]@{
    lower = 0, 'text'; upper = 0, 'text'; trim = 0, 'text'; replace = 2, 'text'; split = 1, 'text'
    join = 1, 'list'; first = 0, 'list'; last = 0, 'list'; sort = 0, 'list'; unique = 0, 'list'; count = 0, 'list'
    keys = 0, 'map'; values = 0, 'map'
}

function Compare-PsdScalar {
    param($A, $B)
    if ((Test-PsdNumber $A) -and (Test-PsdNumber $B)) { return ([double]$A).CompareTo([double]$B) }
    [string]::Compare((Format-PsdScalarText $A), (Format-PsdScalarText $B), [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-PsdFilter {
    param($Filter, $Value, $FArgs, $Ev)
    $ctx = $Ev.Doc.Ctx
    $name = $Filter.Name.ToLowerInvariant()
    $err = {
        param($code, $msg, [string[]] $hint = @())
        Add-PsdNodeError $ctx $code $msg $Ev.Node $Filter.Start ($Filter.End - $Filter.Start) -Hint $hint
        $null
    }
    if (-not $script:PsdFilters.Contains($name)) {
        $all = @($script:PsdFilters.PSBase.Keys) -join ', '
        $dym = Get-PsdDidYouMean $Filter.Name $script:PsdFilters.PSBase.Keys
        return (& $err 'PSD311' "'$($Filter.Name)' isn't a filter." @($dym, "Filters: $all."))
    }
    $want, $kind = $script:PsdFilters[$name]
    if ($FArgs.Count -ne $want) {
        $n = if ($want -eq 1) { '1 argument' } else { "$want arguments" }
        return (& $err 'PSD312' "'$name' takes $n, but got $($FArgs.Count).")
    }
    if ($null -eq $Value) { return $null }
    $okKind = switch ($kind) {
        'text' { $Value -is [string] }
        'list' { Test-PsdList $Value }
        'map' { $Value -is [System.Collections.IDictionary] }
    }
    if (-not $okKind) {
        $what = @{ text = 'text'; list = 'a list'; map = 'a map' }[$kind]
        return (& $err 'PSD312' "'$name' works on $what, but this is $(Get-PsdKindText $Value).")
    }
    $textArgs = New-PsdList
    foreach ($a in $FArgs) {
        if (Test-PsdContainer $a) { return (& $err 'PSD312' "the arguments of '$name' have to be text or numbers.") }
        $textArgs.Add((Format-PsdScalarText $a))
    }
    if ($name -in 'join', 'sort') {
        foreach ($x in $Value) {
            if (Test-PsdContainer $x) { return (& $err 'PSD312' "'$name' needs a list of text or numbers, but an item is $(Get-PsdKindText $x).") }
        }
    }

    switch ($name) {
        'lower' { return $Value.ToLowerInvariant() }
        'upper' { return $Value.ToUpperInvariant() }
        'trim' { return $Value.Trim() }
        'replace' {
            if ($textArgs[0].Length -eq 0) { return (& $err 'PSD312' "'replace' can't replace empty text.") }
            return $Value.Replace($textArgs[0], $textArgs[1])
        }
        'split' {
            $out = New-PsdList
            if ($textArgs[0].Length -eq 0) { foreach ($c in $Value.ToCharArray()) { $out.Add([string]$c) } }
            else { foreach ($p in $Value.Split([string[]]@($textArgs[0]), [System.StringSplitOptions]::None)) { $out.Add($p) } }
            return , $out
        }
        'join' {
            $parts = foreach ($x in $Value) { Format-PsdScalarText $x }
            return ($parts -join $textArgs[0])
        }
        'first' { if ($Value.Count -eq 0) { return $null }; return , $Value[0] }
        'last' { if ($Value.Count -eq 0) { return $null }; return , $Value[$Value.Count - 1] }
        'count' { if ($Value -is [System.Collections.IDictionary]) { return $Value.PSBase.Count }; return $Value.Count }
        'sort' {
            $out = Get-PsdItems $Value
            # Insertion sort keeps equal items in order.
            for ($i = 1; $i -lt $out.Count; $i++) {
                $x = $out[$i]
                $j = $i - 1
                while ($j -ge 0 -and (Compare-PsdScalar $out[$j] $x) -gt 0) { $out[$j + 1] = $out[$j]; $j-- }
                $out[$j + 1] = $x
            }
            return , $out
        }
        'unique' {
            $out = New-PsdList
            foreach ($x in $Value) { if (-not (Test-PsdListHas $out $x)) { $out.Add($x) } }
            return , $out
        }
        'keys' { $out = New-PsdList; foreach ($k in $Value.PSBase.Keys) { $out.Add($k) }; return , $out }
        'values' { $out = New-PsdList; foreach ($k in $Value.PSBase.Keys) { $out.Add($Value[$k]) }; return , $out }
    }
    $null
}
