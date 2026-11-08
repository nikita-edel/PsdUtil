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
            Add-PsdLimitError $ctx 'MaxDepth' "while following references at $($Node.Path)" $Node
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
    $start = $Doc.ResList.IndexOf($Node)
    $chain = $Doc.ResList.GetRange($start, $Doc.ResList.Count - $start)
    $extra = New-PsdList
    $width = 0
    foreach ($n in $chain) { $width = [Math]::Max($width, $n.Path.Length) }
    foreach ($n in $chain) {
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
    if ($Budget -le 0 -or -not (Test-PsdContainer $Value)) { return 1 }
    $items = $Value
    if ($Value -is [System.Collections.IDictionary]) { $items = $Value.PSBase.Values }
    $n = 1
    foreach ($x in $items) { $n += Measure-PsdSize $x ($Budget - $n); if ($n -gt $Budget) { break } }
    $n
}

function Resolve-PsdText {
    param($Node, $Doc)
    $ctx = $Doc.Ctx
    $ev = @{ Doc = $Doc; Node = $Node; InCond = $false; Final = $null }
    $parts = $Node.Parts
    $step = $null
    if ($null -ne $ctx.Trace) {
        $step = @{ Depth = $Doc.RefDepth; Step = $Node.Path; Text = $Node.Text; Value = $null }
        $ctx.Trace.Add($step)
    }

    if ($parts.Count -eq 1 -and $parts[0] -isnot [string]) {
        $v = Invoke-PsdRef $parts[0] $ev
        if (Test-PsdContainer $v) {
            $ctx.Nodes += Measure-PsdSize $v ($ctx.Limits.MaxNodes - $ctx.Nodes + 1)
            if ($ctx.Nodes -gt $ctx.Limits.MaxNodes) {
                Add-PsdLimitError $ctx 'MaxNodes' "while copying values through references at $($Node.Path)" $Node
                return $null
            }
        }
        if ($step) { $step.Value = $v }
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
            Add-PsdLimitError $ctx 'MaxStringLength' "while building the text of $($Node.Path)" $Node
            return $null
        }
    }
    $s = $sb.ToString()
    if ($step) { $step.Value = $s }
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
    if ($null -ne $miss) { return @{ Value = $null; Keep = (Write-PsdUnresolved $miss $Ev $Ref) } }
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
    if ($Ev.InCond -and $code -eq 'PSD301' -and $Miss.Op -and -not $Miss.Op.Ns -and $null -ne $Ev.Final -and (Test-PsdTreePath (Get-PsdAllTree $Ev.Final) $Miss.Op.Segs)) {
        $code = 'PSD401'
        $msg = "this condition reads $(Format-PsdSegs $Miss.Op.Segs), but that is only set inside an !if, and conditions can't see inside an !if."
        $mode = 'Error'
    }
    if ($mode -eq 'Keep') { return $true }
    if ($mode -eq 'Error') { Add-PsdNodeError $ctx $code $msg $Ev.Node ($Ref.Start + $Miss.Start) $Miss.Length -Hint $Miss.Hint }
    elseif ($mode -eq 'Warn') {
        $loc = Get-PsdNodeLoc $Ev.Node ($Ref.Start + $Miss.Start) $Miss.Length
        $where = ''
        if ($loc.File) { $where = "$($loc.File.Name + $loc.File.Ext), line $($loc.Line): " }
        $ctx.Warnings.Add("$where$msg It became `$null.")
    }
    $false
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

    $from = Get-PsdPathStart $Op $Ev $Ref $rel
    if ($null -eq $from) { return $fail }

    if ($Op.Builtin) {
        switch ($Op.Builtin.ToLowerInvariant()) {
            'name' { $ok.Value = $from.File.Ns }
            'file' { $ok.Value = ConvertTo-PsdSlashPath $from.File.Path }
            'dir' { $ok.Value = (ConvertTo-PsdSlashPath $from.File.Dir).TrimEnd('/') }
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

    # $cur is a tree node while $isNode, then a plain value once a reference or a scalar was reached. Either way
    # $data is what can be looked into: a map, a list, a scalar or $null.
    $cur = $from.Root
    $isNode = $true
    $segs = $Op.Segs
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $seg = $segs[$i]
        $segRel = $seg.Start - $Ref.Start
        $segLen = $seg.End - $seg.Start
        $under = Format-PsdSegs $segs $i
        if ($isNode -and $cur.K -in 'T', 'O') { $cur = Get-PsdNodeValue $cur $from.Doc; $isNode = $false }
        elseif ($isNode -and $cur.K -eq 'S') { $cur = $cur.V; $isNode = $false }
        $data = $cur
        if ($isNode) { $data = $cur.V }

        if ($null -eq $data) {
            $what = if ($seg.IsIndex) { "[$($seg.Index)]" } else { "'$($seg.Key)'" }
            return (New-PsdMiss 'PSD301' "$what can't be read, because $under is `$null." $segRel $segLen @() $Op)
        }
        if (-not (Test-PsdContainer $data)) {
            Add-PsdNodeError $ctx 'PSD304' "$under is $(Get-PsdKindText $data), so it has nothing inside it to read." $Ev.Node $seg.Start $segLen
            return $fail
        }
        if ($data -is [System.Collections.IDictionary]) {
            if ($seg.IsIndex) {
                Add-PsdNodeError $ctx 'PSD308' "$under is a map, so [$($seg.Index)] can't be used on it. Use a key: $under.Name" $Ev.Node $seg.Start $segLen
                return $fail
            }
            if (-not $data.Contains($seg.Key)) { return (New-PsdKeyMiss $Op $from $data $i $segRel $doc) }
            $cur = $data[$seg.Key]
            continue
        }
        if (-not $seg.IsIndex) {
            Add-PsdNodeError $ctx 'PSD308' "$under is a list, so .$($seg.Key) can't be used on it. Use an index: $under[0]" $Ev.Node $seg.Start $segLen
            return $fail
        }
        $idx = $seg.Index
        if ($idx -lt 0) { $idx += $data.Count }
        if ($idx -lt 0 -or $idx -ge $data.Count) {
            $items = if ($data.Count -eq 1) { '1 item' } else { "$($data.Count) items" }
            return (New-PsdMiss 'PSD307' "$under has $items, so [$($seg.Index)] doesn't exist." $segRel $segLen @() $Op)
        }
        $cur = $data[$idx]
    }
    if ($isNode) { $ok.Value = Get-PsdNodeValue $cur $from.Doc } else { $ok.Value = $cur }
    if ($from.AlsoIn.Count -gt 0) { Add-PsdSourceNote $ctx $Ev $Op $from.AlsoIn }
    $ok
}

# Where a path starts. Returns $null after reporting an error, or:
#   File, Doc, Root  the file, its document and the tree the path is read from ($null Root for a built-in)
#   Via              the include a key without name:: was read from, because this file doesn't have it
#   AlsoIn           includes that have the first key too, when this file has it: named in a note or a hint
#   IncludeKeys      keys of the includes, for "did you mean" when a key without name:: is nowhere
function Get-PsdPathStart {
    param($Op, $Ev, $Ref, [int] $Rel)
    $doc = $Ev.Doc
    $from = @{ File = $doc.Entry; Doc = $doc; Root = $null; Via = $null; AlsoIn = (New-PsdList); IncludeKeys = (New-PsdList) }
    if ($Op.Ns) {
        # The namespace sits at the start of the operand, after an optional '?'.
        $t = Get-PsdNsFile $Op $Ev ($Ref.Start + $Ref.Raw.IndexOf($Op.Ns, $Rel))
        if ($null -eq $t) { return $null }
        $from.File = $t.File
        $from.Doc = $t.Doc
        if (-not $Op.Builtin) {
            if ($t.Own) { $from.Root = Get-PsdOwnTree $t.Doc $t.File } else { $from.Root = $t.Doc.Tree }
        }
        return $from
    }
    if ($Op.Builtin) { return $from }

    # A key that isn't in this document is read from the one include that has it, exactly as if name:: were
    # written. Several includes with it are an error, so nothing depends on their order.
    $from.Root = $doc.Tree
    $first = $Op.Segs[0]
    $byKey = -not $first.IsIndex -and $doc.Tree.K -eq 'M'
    $hits = New-PsdList
    if ($byKey) {
        foreach ($name in @($doc.Inc.PSBase.Keys | Sort-Object)) {
            $t = $doc.Inc[$name].Tree
            if ($null -ne $t -and $t.K -eq 'M') {
                foreach ($k in $t.V.PSBase.Keys) { $from.IncludeKeys.Add($k) }
                if ($t.V.Contains($first.Key)) { $hits.Add($name) }
            }
        }
    }
    if ($byKey -and $doc.Tree.V.Contains($first.Key)) { $from.AlsoIn = $hits; return $from }
    if ($hits.Count -gt 1) {
        $choices = @($hits | ForEach-Object { "!<$($_)::$(Format-PsdSegs $Op.Segs)>" }) -join ' or '
        Add-PsdNodeError $doc.Ctx 'PSD313' "'$($first.Key)' isn't in this file but in $($hits.Count) includes: $($hits -join ', '), so it's unclear which one is meant." $Ev.Node $first.Start ($first.End - $first.Start) -Hint @("Write the one you mean: $choices.")
        return $null
    }
    if ($hits.Count -eq 1) {
        $from.Via = $hits[0]
        $from.Doc = $doc.Inc[$hits[0]]
        $from.File = $from.Doc.Entry
        $from.Root = $from.Doc.Tree
    }
    $from
}

# The miss for key number At of a path, which isn't in Map, with what the includes can tell about it.
function New-PsdKeyMiss {
    param($Op, $From, $Map, [int] $At, [int] $Rel, $Doc)
    $segs = $Op.Segs
    $seg = $segs[$At]
    $in = ''
    if ($Op.Ns) { $in = " in $($From.File.Name + $From.File.Ext)" }
    elseif ($From.Via) { $in = " in the include $($From.Via)" }
    if ($At -eq 0) { $msg = "'$($seg.Key)' doesn't exist$in." } else { $msg = "'$($seg.Key)' doesn't exist under $(Format-PsdSegs $segs $At)$in." }
    $candidates = @($Map.PSBase.Keys)
    if ($At -eq 0 -and -not $Op.Ns) {
        if ($From.IncludeKeys.Count -gt 0) { $msg = "'$($seg.Key)' doesn't exist in this file or its includes." }
        # ToArray: @() on a generic list fails
        $candidates += $From.IncludeKeys.ToArray()
    }
    $hint = New-PsdList
    $dym = Get-PsdDidYouMean $seg.Key $candidates
    if ($dym) { $hint.Add($dym) }
    if ($From.Via) {
        $hint.Add("This file and its merge chain have no $($segs[0].Key), so it was read from the include $($From.Via), the only one that has it.")
    }
    if ($At -gt 0 -and $From.AlsoIn.Count -gt 0) {
        $path = Format-PsdSegs $segs
        foreach ($name in $From.AlsoIn) {
            if (Test-PsdTreePath $Doc.Inc[$name].Tree $segs) { $hint.Add("The include $name has $($path): !<$($name)::$path> reads it.") }
            else { $hint.Add("The include $name has $($segs[0].Key) too, but not $path.") }
        }
        $hint.Add("Without name::, $($segs[0].Key) is read from this file and its merge chain because they have it, and the includes aren't looked at.")
    }
    New-PsdMiss 'PSD301' $msg $Rel ($seg.End - $seg.Start) $hint.ToArray() $Op
}

# The child of a tree node for one step of a path, or $null. Resolves nothing.
function Get-PsdTreeChild {
    param($Node, $Seg)
    if ($Seg.IsIndex) {
        if ($Node.K -ne 'L') { return $null }
        $i = $Seg.Index
        if ($i -lt 0) { $i += $Node.V.Count }
        if ($i -ge 0 -and $i -lt $Node.V.Count) { return $Node.V[$i] }
        return $null
    }
    if ($Node.K -eq 'M' -and $Node.V.Contains($Seg.Key)) { return $Node.V[$Seg.Key] }
    $null
}

function Test-PsdTreePath {
    param($Tree, $Segs)
    $cur = $Tree
    foreach ($seg in $Segs) {
        if ($null -eq $cur) { return $false }
        $cur = Get-PsdTreeChild $cur $seg
    }
    $null -ne $cur
}

# Notes, for -Verbose, that a reference without name:: read a key of this file that includes have too: where the
# value came from and how to read the other ones. Once per place.
function Add-PsdSourceNote {
    param($Ctx, $Ev, $Op, $AlsoIn)
    $first = $Op.Segs[0]
    $loc = Get-PsdNodeLoc $Ev.Node $first.Start ($first.End - $first.Start)
    $path = Format-PsdSegs $Op.Segs
    $where = ''
    if ($loc.File) {
        $label = if ($loc.File.Synthetic) { $loc.File.Label } else { $loc.File.Name + $loc.File.Ext }
        $where = if ($loc.Line -gt 0) { "$label, line $($loc.Line): " } else { "${label}: " }
    }
    $sig = "$where|$path"
    if ($Ctx.NoteSeen.ContainsKey($sig)) { return }
    $Ctx.NoteSeen[$sig] = $true
    $names = $AlsoIn.ToArray()
    $verb = if ($names.Count -gt 1) { "The includes $($names -join ', ') have" } else { "The include $($names[0]) has" }
    $reads = @($names | ForEach-Object { "!<$($_)::$path>" }) -join ' or '
    $Ctx.Notes.Add("$where!<$path> reads $($first.Key) from this file and its merge chain. $verb $($first.Key) too; $reads reads that one.")
}

function Resolve-PsdOp {
    param($Node, $Doc)
    $ctx = $Doc.Ctx
    $base = $null
    if ($null -ne $Node.Base) { $base = Get-PsdNodeValue $Node.Base $Doc }
    $arg = Get-PsdNodeValue $Node.Arg $Doc
    $shown = $Node.Path
    $argItems = Get-PsdItems $arg
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
    if ($null -ne $base -and -not (Test-PsdList $base)) {
        & $err 'PSD210' "$($Node.Op) only works on lists, but $shown is $(Get-PsdKindText $base)."
        return , $base
    }
    $items = New-PsdList
    foreach ($x in $base) { $items.Add($x) }
    switch ($Node.Op) {
        '+=' { foreach ($a in $argItems) { $items.Add($a) } }
        '=+' { foreach ($x in $items) { $argItems.Add($x) }; $items = $argItems }
        '|=' { foreach ($a in $argItems) { if (-not (Test-PsdListHas $items $a)) { $items.Add($a) } } }
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
