# Works out references on demand. Each value is worked out once per document;
# a value that is reached again while it's being worked out is a cycle.

function Get-PsdNodeValue {
    param($Node, $Doc)
    if ($Node.K -eq 'S') { return , $Node.V }
    if ($Doc.Cache.ContainsKey($Node.Id)) { return , $Doc.Cache[$Node.Id] }
    $ctx = $Doc.Ctx
    if ($ctx.LimitHit) { return $null }
    if ($Doc.ResSet.ContainsKey($Node.Id)) {
        Add-PsdCycleError $Node $Doc
        return $null
    }
    $isRef = ($Node.K -eq 'T' -or $Node.K -eq 'O')
    if ($isRef) {
        $Doc.RefDepth++
        if ($Doc.RefDepth -gt $ctx.Limits.MaxDepth) {
            $Doc.RefDepth--
            $loc = Get-PsdNodeLoc $Node
            Add-PsdLimitError $ctx 'MaxDepth' "while following references at $($Node.Path)" $loc.File $loc.Line $loc.Col
            return $null
        }
    }
    $Doc.ResSet[$Node.Id] = $true
    $Doc.ResList.Add($Node)
    $value = $null
    try {
        switch ($Node.K) {
            'M' {
                $value = [ordered]@{}
                foreach ($k in $Node.V.PSBase.Keys) { $value[$k] = Get-PsdNodeValue $Node.V[$k] $Doc }
            }
            'L' {
                $value = New-PsdList
                foreach ($x in $Node.V) { $value.Add((Get-PsdNodeValue $x $Doc)) }
            }
            'T' { $value = Resolve-PsdText $Node $Doc }
            'O' { $value = Resolve-PsdOp $Node $Doc }
        }
    }
    finally {
        $Doc.ResSet.Remove($Node.Id)
        $Doc.ResList.RemoveAt($Doc.ResList.Count - 1)
        if ($isRef) { $Doc.RefDepth-- }
    }
    $Doc.Cache[$Node.Id] = $value
    , $value
}

function Add-PsdCycleError {
    param($Node, $Doc)
    $start = 0
    for ($i = 0; $i -lt $Doc.ResList.Count; $i++) { if ($Doc.ResList[$i].Id -eq $Node.Id) { $start = $i; break } }
    $extra = New-PsdList
    $width = 0
    for ($i = $start; $i -lt $Doc.ResList.Count; $i++) { $width = [Math]::Max($width, [string]$Doc.ResList[$i].Path.Length) }
    for ($i = $start; $i -lt $Doc.ResList.Count; $i++) {
        $n = $Doc.ResList[$i]
        $label = $n.Path
        if (-not $label) { $label = '(the whole file)' }
        $where = ''
        if ($n.Line -gt 0) { $where = "line $($n.Line)" }
        if ($n.File -and $n.File.Key -ne $Node.File.Key) { $where = "$($n.File.Name + $n.File.Ext) $where" }
        $what = '(contains it)'
        if ($n.K -eq 'T') { $what = $n.Text }
        if ($n.K -eq 'O') { $what = $n.Text + ' operator' }
        $extra.Add(('{0}    {1,-14} {2}' -f $label.PadRight($width), $where, $what).TrimEnd())
    }
    $first = $Node.Path
    if (-not $first) { $first = 'the whole file' }
    $extra.Add("... and back to $first")
    $extra.Add('')
    $loc = Get-PsdNodeLoc $Node
    Add-PsdError $Doc.Ctx 'PSD303' "these values depend on each other, so they can't be worked out." -File $loc.File -Line $loc.Line -Column $loc.Col -Length $loc.Len -Key $Node.Path `
        -Extra $extra -Hint @('Give one of them a real value.')
}

function Measure-PsdSize {
    param($Value, [int] $Budget)
    if ($Budget -le 0) { return 1 }
    if ($Value -is [System.Collections.IDictionary]) {
        $n = 1
        foreach ($k in $Value.PSBase.Keys) { $n += Measure-PsdSize $Value[$k] ($Budget - $n); if ($n -gt $Budget) { break } }
        return $n
    }
    if (Test-PsdList $Value) {
        $n = 1
        foreach ($x in $Value) { $n += Measure-PsdSize $x ($Budget - $n); if ($n -gt $Budget) { break } }
        return $n
    }
    1
}

function Resolve-PsdText {
    param($Node, $Doc)
    $ctx = $Doc.Ctx
    $ev = @{ Doc = $Doc; Node = $Node; InCond = $false; Final = $null }
    $parts = $Node.Parts
    if ($null -ne $ctx.Trace) { $ctx.Trace.Add(@{ Depth = $Doc.RefDepth; Step = $Node.Path; Text = $Node.Text; Value = $null; Pending = $true }) }
    $traceIdx = -1
    if ($null -ne $ctx.Trace) { $traceIdx = $ctx.Trace.Count - 1 }

    if ($parts.Count -eq 1 -and $parts[0] -isnot [string]) {
        $v = Invoke-PsdRef $parts[0] $ev
        if (Test-PsdContainer $v) {
            $ctx.Nodes += Measure-PsdSize $v ($ctx.Limits.MaxNodes - $ctx.Nodes + 1)
            if ($ctx.Nodes -gt $ctx.Limits.MaxNodes) {
                $loc = Get-PsdNodeLoc $Node
                Add-PsdLimitError $ctx 'MaxNodes' "while copying values through references at $($Node.Path)" $loc.File $loc.Line $loc.Col
                return $null
            }
        }
        if ($traceIdx -ge 0) { $ctx.Trace[$traceIdx].Value = $v; $ctx.Trace[$traceIdx].Pending = $false }
        return , $v
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($part in $parts) {
        if ($part -is [string]) { [void]$sb.Append($part); continue }
        $v = Invoke-PsdRef $part $ev
        if (Test-PsdContainer $v) {
            $kind = Get-PsdKindText $v
            $shown = $part.Raw.Substring(2, $part.Raw.Length - 3).Trim()
            Add-PsdNodeError $ctx 'PSD306' "$shown is $kind, so it can't go inside text." $Node $part.Start ($part.End - $part.Start) `
                -Hint @('Use one of its keys or items, or make the reference the whole value.')
            continue
        }
        [void]$sb.Append((Format-PsdScalarText $v))
        if ($sb.Length -gt $ctx.Limits.MaxStringLength) {
            $loc = Get-PsdNodeLoc $Node
            Add-PsdLimitError $ctx 'MaxStringLength' "while building the text of $($Node.Path)" $loc.File $loc.Line $loc.Col
            return $null
        }
    }
    $s = $sb.ToString()
    if ($traceIdx -ge 0) { $ctx.Trace[$traceIdx].Value = $s; $ctx.Trace[$traceIdx].Pending = $false }
    $s
}

function Invoke-PsdRef {
    param($Ref, $Ev)
    $r = Invoke-PsdExpr $Ref.Expr $Ev $Ref
    if ($r.Keep) { return $Ref.Raw }
    , $r.Value
}

# Returns @{ Value; Keep }. Keep means: leave the reference as it was written.
function Invoke-PsdExpr {
    param($Expr, $Ev, $Ref)
    $value = $null
    $miss = $null
    foreach ($op in $Expr.Ops) {
        if ($op.T -eq 'Lit') { $found = $true; $v = $op.V }
        else {
            $r = Get-PsdPathValue $op $Ev $Ref
            if ($r.Failed) { return @{ Value = $null; Keep = $false } }
            $found = $r.Found
            $v = $r.Value
            if (-not $found -and $op.Optional) { $found = $true; $v = $null }
            if (-not $found) { $miss = $r }
        }
        if ($found) {
            $miss = $null
            if ($null -ne $v) { $value = $v; break }
        }
    }
    if ($null -ne $miss) {
        $keep = Write-PsdUnresolved $miss $Ev $Ref
        if ($keep) { return @{ Value = $null; Keep = $true } }
        return @{ Value = $null; Keep = $false }
    }
    $ctx = $Ev.Doc.Ctx
    foreach ($f in $Expr.Filters) {
        $fargs = New-PsdList
        foreach ($a in $f.Args) {
            $ar = Invoke-PsdExpr $a $Ev $Ref
            $fargs.Add($ar.Value)
        }
        $value = Invoke-PsdFilter $f $value $fargs $Ev
        if ($null -ne $ctx.Trace) {
            $ctx.Trace.Add(@{ Depth = $Ev.Doc.RefDepth + 1; Step = "| $($f.Name)"; Text = $null; Value = $value; Pending = $false })
        }
    }
    @{ Value = $value; Keep = $false }
}

function Write-PsdUnresolved {
    param($Miss, $Ev, $Ref)
    $ctx = $Ev.Doc.Ctx
    $mode = $ctx.Unresolved
    $code = $Miss.Code
    $msg = $Miss.Message
    if ($Ev.InCond -and $code -eq 'PSD301' -and $Miss.Op -and -not $Miss.Op.Ns -and (Test-PsdAllTreeHas $Ev.Final $Miss.Op)) {
        $code = 'PSD401'
        $msg = "this condition reads $(Format-PsdSegs $Miss.Op.Segs), but that is only set inside an !if, and conditions can't see inside an !if."
        $mode = 'Error'
    }
    switch ($mode) {
        'Error' {
            Add-PsdNodeError $ctx $code $msg $Ev.Node ($Ref.Start + $Miss.Start) $Miss.Length -Hint $Miss.Hint
            return $false
        }
        'Warn' {
            $loc = Get-PsdNodeLoc $Ev.Node ($Ref.Start + $Miss.Start) $Miss.Length
            $where = ''
            if ($loc.File) { $where = "$($loc.File.Name + $loc.File.Ext), line $($loc.Line): " }
            $ctx.Warnings.Add("$where$msg It became `$null.")
            return $false
        }
        'Keep' { return $true }
    }
    $false
}

function Test-PsdAllTreeHas {
    param($Doc, $Op)
    if ($null -eq $Doc) { return $false }
    $cur = Get-PsdAllTree $Doc
    foreach ($seg in $Op.Segs) {
        if ($seg.IsIndex -or $cur.K -ne 'M' -or -not $cur.V.Contains($seg.Key)) { return $false }
        $cur = $cur.V[$seg.Key]
    }
    $true
}

function New-PsdMiss {
    param([string] $Code, [string] $Message, [int] $Start, [int] $Length, [string[]] $Hint = @(), $Op = $null)
    @{ Found = $false; Failed = $false; Value = $null; Code = $Code; Message = $Message; Start = $Start; Length = $Length; Hint = $Hint; Op = $Op }
}

function Get-PsdNsFile {
    param($Op, $Ev, [int] $At)
    $doc = $Ev.Doc
    $ns = $Op.Ns
    if ($ns -ieq 'this') { return @{ File = $Ev.Node.File; Doc = $doc; Own = $true } }
    if ($doc.Ns.ContainsKey($ns)) { return @{ File = $doc.Ns[$ns]; Doc = $doc; Own = $true } }
    if ($doc.Inc.ContainsKey($ns)) { $d = $doc.Inc[$ns]; return @{ File = $d.Entry; Doc = $d; Own = $false } }
    $names = New-PsdList
    $names.Add('this')
    foreach ($k in @($doc.Ns.PSBase.Keys | Sort-Object)) { $names.Add($k) }
    foreach ($k in @($doc.Inc.PSBase.Keys | Sort-Object)) { $names.Add($k) }
    $hint = @((Get-PsdDidYouMean $ns $names), "You can use: $($names -join ', ')")
    Add-PsdNodeError $doc.Ctx 'PSD302' "there is no file called '$ns' in this chain or its includes." $Ev.Node $At $ns.Length -Hint $hint
    $null
}

function Get-PsdPathValue {
    param($Op, $Ev, $Ref)
    $doc = $Ev.Doc
    $ctx = $doc.Ctx
    $rel = $Op.Start - $Ref.Start
    $opText = $Ref.Raw.Substring($rel, $Op.End - $Op.Start)
    $ok = @{ Found = $true; Failed = $false; Value = $null }
    $fail = @{ Found = $false; Failed = $true; Value = $null }

    if ($Op.Env) {
        $v = [Environment]::GetEnvironmentVariable($Op.Env)
        if ($null -eq $v) {
            return (New-PsdMiss 'PSD310' "the environment variable $($Op.Env) isn't set." $rel $opText.Length `
                    @("Set it, or add a fallback: !<env:$($Op.Env) ?? ""..."">") $Op)
        }
        $ok.Value = $v
        return $ok
    }

    $file = $doc.Entry
    $tdoc = $doc
    $root = $null
    if ($Op.Ns) {
        # The namespace sits at the start of the operand, after an optional '?'.
        $nsStart = $Ref.Raw.IndexOf($Op.Ns, $rel)
        $t = Get-PsdNsFile $Op $Ev ($Ref.Start + $nsStart)
        if ($null -eq $t) { return $fail }
        $file = $t.File
        $tdoc = $t.Doc
        if (-not $Op.Builtin) {
            if ($t.Own) { $root = Get-PsdOwnTree $tdoc $file } else { $root = $tdoc.Tree }
        }
    }
    elseif (-not $Op.Builtin) { $root = $doc.Tree }

    if ($Op.Builtin) {
        switch ($Op.Builtin.ToLowerInvariant()) {
            'name' { $ok.Value = $file.Ns }
            'file' { $ok.Value = ConvertTo-PsdSlashPath $file.Path }
            'dir' { $ok.Value = (ConvertTo-PsdSlashPath $file.Dir).TrimEnd('/') }
            'os' { $ok.Value = Get-PsdOsName }
            default {
                $at = $Ref.Raw.IndexOf('@', $rel)
                Add-PsdNodeError $ctx 'PSD309' "@$($Op.Builtin) isn't a built-in." $Ev.Node ($Ref.Start + $at) ($Op.Builtin.Length + 1) `
                    -Hint @((Get-PsdDidYouMean $Op.Builtin @('name', 'file', 'dir', 'os')), 'Built-ins are @name, @file, @dir and @os.')
                return $fail
            }
        }
        return $ok
    }

    $cur = $root
    $isNode = $true
    $segs = $Op.Segs
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $seg = $segs[$i]
        $segRel = $seg.Start - $Ref.Start
        $segLen = $seg.End - $seg.Start
        $under = Format-PsdSegs $segs $i
        if ($isNode) {
            if ($cur.K -eq 'T' -or $cur.K -eq 'O') { $cur = Get-PsdNodeValue $cur $tdoc; $isNode = $false }
            elseif ($cur.K -eq 'S') { $cur = $cur.V; $isNode = $false }
        }
        $kindNow = $null
        $keys = $null
        $count = 0
        if ($isNode) {
            if ($cur.K -eq 'M') { $kindNow = 'map'; $keys = $cur.V.PSBase.Keys }
            else { $kindNow = 'list'; $count = $cur.V.Count }
        }
        elseif ($null -eq $cur) { $kindNow = 'null' }
        elseif ($cur -is [System.Collections.IDictionary]) { $kindNow = 'map'; $keys = $cur.PSBase.Keys }
        elseif (Test-PsdList $cur) { $kindNow = 'list'; $count = $cur.Count }
        else { $kindNow = 'scalar' }

        if ($kindNow -eq 'null') {
            $what = if ($seg.IsIndex) { "[$($seg.Index)]" } else { "'$($seg.Key)'" }
            return (New-PsdMiss 'PSD301' "$what can't be read, because $under is `$null." $segRel $segLen @() $Op)
        }
        if ($kindNow -eq 'scalar') {
            Add-PsdNodeError $ctx 'PSD304' "$under is $(Get-PsdKindText $cur), so it has nothing inside it to read." $Ev.Node ($Ref.Start + $segRel) $segLen
            return $fail
        }
        if ($kindNow -eq 'map') {
            if ($seg.IsIndex) {
                Add-PsdNodeError $ctx 'PSD308' "$under is a map, so [$($seg.Index)] can't be used on it. Use a key: $under.Name" $Ev.Node ($Ref.Start + $segRel) $segLen
                return $fail
            }
            $has = $false
            if ($isNode) { $has = $cur.V.Contains($seg.Key) } else { $has = $cur.Contains($seg.Key) }
            if (-not $has) {
                $in = ''
                if ($Op.Ns) { $in = " in $($file.Name + $file.Ext)" }
                if ($i -eq 0) { $msg = "'$($seg.Key)' doesn't exist$in." } else { $msg = "'$($seg.Key)' doesn't exist under $under$in." }
                return (New-PsdMiss 'PSD301' $msg $segRel $segLen @((Get-PsdDidYouMean $seg.Key $keys)) $Op)
            }
            if ($isNode) { $cur = $cur.V[$seg.Key] } else { $cur = $cur[$seg.Key] }
            continue
        }
        if (-not $seg.IsIndex) {
            Add-PsdNodeError $ctx 'PSD308' "$under is a list, so .$($seg.Key) can't be used on it. Use an index: $under[0]" $Ev.Node ($Ref.Start + $segRel) $segLen
            return $fail
        }
        $idx = $seg.Index
        if ($idx -lt 0) { $idx += $count }
        if ($idx -lt 0 -or $idx -ge $count) {
            $items = if ($count -eq 1) { '1 item' } else { "$count items" }
            return (New-PsdMiss 'PSD307' "$under has $items, so [$($seg.Index)] doesn't exist." $segRel $segLen @() $Op)
        }
        if ($isNode) { $cur = $cur.V[$idx] } else { $cur = $cur[$idx] }
    }
    if ($isNode) { $ok.Value = Get-PsdNodeValue $cur $tdoc } else { $ok.Value = $cur }
    $ok
}

function Resolve-PsdOp {
    param($Node, $Doc)
    $ctx = $Doc.Ctx
    $base = $null
    if ($null -ne $Node.Base) { $base = Get-PsdNodeValue $Node.Base $Doc }
    $arg = Get-PsdNodeValue $Node.Arg $Doc
    $shown = $Node.Path
    $argItems = New-PsdList
    if (Test-PsdList $arg) { foreach ($x in $arg) { $argItems.Add($x) } } else { $argItems.Add($arg) }
    $err = {
        param($code, $msg)
        Add-PsdError $ctx $code $msg -File $Node.File -Line $Node.Line -Column $Node.Col -Length $Node.KeyLen -Key $Node.Path
    }

    if ($base -is [System.Collections.IDictionary]) {
        if ($Node.Op -ne '-=') { & $err 'PSD210' "$($Node.Op) only works on lists, but $shown is a map."; return , $base }
        $out = [ordered]@{}
        foreach ($k in $base.PSBase.Keys) { $out[$k] = $base[$k] }
        foreach ($a in $argItems) {
            if ($a -isnot [string]) { & $err 'PSD211' "removing from the map $shown needs key names."; continue }
            if ($out.Contains($a)) { $out.Remove($a) } else { & $err 'PSD212' "'$a' isn't a key of $shown, so it can't be removed." }
        }
        return , $out
    }
    $items = New-PsdList
    if (Test-PsdList $base) { foreach ($x in $base) { $items.Add($x) } }
    elseif ($null -ne $base) {
        & $err 'PSD210' "$($Node.Op) only works on lists, but $shown is $(Get-PsdKindText $base)."
        return , $base
    }
    switch ($Node.Op) {
        '+=' { foreach ($a in $argItems) { $items.Add($a) } }
        '=+' { $new = New-PsdList; foreach ($a in $argItems) { $new.Add($a) }; foreach ($x in $items) { $new.Add($x) }; $items = $new }
        '|=' {
            foreach ($a in $argItems) {
                $there = $false
                foreach ($x in $items) { if (Test-PsdEqual $x $a) { $there = $true; break } }
                if (-not $there) { $items.Add($a) }
            }
        }
        '-=' {
            foreach ($a in $argItems) {
                $kept = New-PsdList
                $hit = $false
                foreach ($x in $items) { if (Test-PsdEqual $x $a) { $hit = $true } else { $kept.Add($x) } }
                if (-not $hit) { & $err 'PSD212' "$(Format-PsdValueShort $a) isn't in $shown, so it can't be removed." }
                $items = $kept
            }
        }
    }
    , $items
}
