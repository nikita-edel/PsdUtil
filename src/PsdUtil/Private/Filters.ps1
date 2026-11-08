# The fixed list of filters. None of them can loop.

$script:PsdFilterArgs = [ordered]@{
    lower = 0; upper = 0; trim = 0; replace = 2; split = 1
    join = 1; first = 0; last = 0; sort = 0; unique = 0; count = 0
    keys = 0; values = 0
}
$script:PsdFilterKinds = @{
    lower = 'text'; upper = 'text'; trim = 'text'; replace = 'text'; split = 'text'
    join = 'list'; first = 'list'; last = 'list'; sort = 'list'; unique = 'list'; count = 'list'
    keys = 'map'; values = 'map'
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
    if (-not $script:PsdFilterArgs.Contains($name)) {
        $all = @($script:PsdFilterArgs.PSBase.Keys) -join ', '
        $dym = Get-PsdDidYouMean $Filter.Name $script:PsdFilterArgs.PSBase.Keys
        return (& $err 'PSD311' "'$($Filter.Name)' isn't a filter." @($dym, "Filters: $all."))
    }
    $want = $script:PsdFilterArgs[$name]
    if ($FArgs.Count -ne $want) {
        $n = if ($want -eq 1) { '1 argument' } else { "$want arguments" }
        return (& $err 'PSD312' "'$name' takes $n, but got $($FArgs.Count).")
    }
    if ($null -eq $Value) { return $null }
    $kind = $script:PsdFilterKinds[$name]
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
            $parts = New-PsdList
            foreach ($x in $Value) {
                if (Test-PsdContainer $x) { return (& $err 'PSD312' "'join' needs a list of text or numbers, but an item is $(Get-PsdKindText $x).") }
                $parts.Add((Format-PsdScalarText $x))
            }
            return ($parts -join $textArgs[0])
        }
        'first' { if ($Value.Count -eq 0) { return $null }; return , $Value[0] }
        'last' { if ($Value.Count -eq 0) { return $null }; return , $Value[$Value.Count - 1] }
        'count' { if ($Value -is [System.Collections.IDictionary]) { return $Value.PSBase.Count }; return $Value.Count }
        'sort' {
            $out = New-PsdList
            foreach ($x in $Value) {
                if (Test-PsdContainer $x) { return (& $err 'PSD312' "'sort' needs a list of text or numbers, but an item is $(Get-PsdKindText $x).") }
                $out.Add($x)
            }
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
            foreach ($x in $Value) {
                $there = $false
                foreach ($y in $out) { if (Test-PsdEqual $x $y) { $there = $true; break } }
                if (-not $there) { $out.Add($x) }
            }
            return , $out
        }
        'keys' { $out = New-PsdList; foreach ($k in $Value.PSBase.Keys) { $out.Add($k) }; return , $out }
        'values' { $out = New-PsdList; foreach ($k in $Value.PSBase.Keys) { $out.Add($Value[$k]) }; return , $out }
    }
    $null
}
