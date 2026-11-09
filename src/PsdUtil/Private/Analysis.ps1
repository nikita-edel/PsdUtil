# The analysis step of a load, between reading files and merging them. It finds what can't be known up front: each
# !if and each path with a reference. It decides them in an order where each one sees everything that can change what
# it reads. Files behind a true !if are loaded as it goes. Files behind a false !if are never read, because reading a
# .ps1 through -Loader runs it.

# The '!merge' or '!include' entries of a file that count now: its own, then those of the true !if in it.
# Returns @{ Entry; Via }. Via has the ids of the !if the entry is inside of, or is $null.
function Get-PsdActiveEntries {
    param($File, [string] $Kind, $Doc)
    $out = New-PsdList
    foreach ($e in $File.$Kind) { $out.Add(@{ Entry = $e; Via = $null }) }
    if ($null -ne $File.Root) { Add-PsdIfEntries $File.Root $Kind $Doc @() $out }
    , $out
}

function Add-PsdIfEntries {
    param($Map, [string] $Kind, $Doc, [object[]] $Via, $Out)
    foreach ($if in $Map.Ifs) {
        if (-not $Doc.Decisions[$if.Id]) { continue }
        $owners = @($Via) + $if.Id
        foreach ($e in $if.Body.$Kind) { $Out.Add(@{ Entry = $e; Via = $owners }) }
        Add-PsdIfEntries $if.Body $Kind $Doc $owners $Out
    }
}

# The path of an entry, or $null while a reference in it isn't decided.
function Get-PsdEntryPath {
    param($Entry, $Doc)
    if ($null -eq $Entry.Ref) { return $Entry.Path }
    $Doc.Paths[$Entry.Ref.Id]
}

# Follows the files of the document again: its layers, the names of its files and its includes.
function Update-PsdDocFiles {
    param($Doc, $Sources)
    $ctx = $Doc.Ctx
    $layers = New-PsdList
    foreach ($s in $Sources) {
        if ($s.ContainsKey('Layer')) { $layers.Add($s.Layer) }
        else { foreach ($l in (Get-PsdLayers $s.File $ctx $Doc)) { $layers.Add($l) } }
    }
    $Doc.Layers = $layers
    $Doc.AllTree = $null
    foreach ($l in $layers) {
        $f = $l.File
        if (-not $f.Synthetic -or $f.Named) { Register-PsdNs $Doc $Doc.Ns $f.Ns $f $f $null $ctx }
    }
    foreach ($l in $layers) {
        foreach ($a in (Get-PsdActiveEntries $l.File 'Include' $Doc)) {
            $path = Get-PsdEntryPath $a.Entry $Doc
            if (-not $path) { continue }
            foreach ($p in (Resolve-PsdPaths $path $l.File $a.Entry.Node $ctx)) {
                $f = Read-PsdFile $p $ctx $a.Entry.Node 'PSD200'
                if ($null -eq $f -or $null -eq $f.Root) { continue }
                $idoc = Get-PsdIncludedDoc $f $ctx $a.Entry.Node
                if ($null -ne $idoc) { Register-PsdNs $Doc $Doc.Inc $f.Ns $f $idoc $a.Entry.Node $ctx }
            }
        }
    }
}

# The document as far as it is decided: true !if are merged, the others are left out.
function New-PsdPartialDoc {
    param($Doc)
    $pre = New-PsdDocObject $Doc.Entry $Doc.Layers $Doc.Ctx
    $pre.Ns = $Doc.Ns
    $pre.Inc = $Doc.Inc
    $pre.Rules = $Doc.Rules
    $pre.Defaults = $Doc.Defaults
    $pre.Decisions = $Doc.Decisions
    $pre.Paths = $Doc.Paths
    $pre.Final = $Doc
    $pre.Tree = Merge-PsdLayers $pre $true
    $pre
}

function New-PsdOpenItem {
    param([string] $Kind, $Id, $Node)
    @{ Kind = $Kind; Id = $Id; Node = $Node; Reads = @{}; Writes = @{}; Loads = $true; Result = $null; Round = 0; Partial = $null }
}

# True when the body of an !if loads a file, so what it writes can't be known yet.
function Test-PsdMapLoads {
    param($Map)
    if ($Map.Merge.Count) { return $true }
    foreach ($if in $Map.Ifs) { if (Test-PsdMapLoads $if.Body) { return $true } }
    $false
}

function Add-PsdOpenInNode {
    param($Node, $Doc, $Out, $Seen)
    if ($Node.K -eq 'M') { Add-PsdOpenIfs $Node $Doc $Out $Seen }
    elseif ($Node.K -eq 'L') { foreach ($x in $Node.V) { Add-PsdOpenInNode $x $Doc $Out $Seen } }
}

function Add-PsdOpenIfs {
    param($Map, $Doc, $Out, $Seen)
    foreach ($k in $Map.V.PSBase.Keys) { Add-PsdOpenInNode $Map.V[$k] $Doc $Out $Seen }
    foreach ($op in $Map.Ops) { Add-PsdOpenInNode $op.Arg $Doc $Out $Seen }
    foreach ($if in $Map.Ifs) {
        if ($Doc.Decisions.ContainsKey($if.Id)) {
            if ($Doc.Decisions[$if.Id]) { Add-PsdOpenIfs $if.Body $Doc $Out $Seen }
        }
        elseif (-not $Seen.ContainsKey($if.Id)) {
            $Seen[$if.Id] = $true
            $Out.Add((New-PsdOpenItem 'If' $if.Id $if))
        }
    }
}

# What is still to be decided in the files loaded so far.
function Get-PsdOpenItems {
    param($Doc)
    $out = New-PsdList
    $seen = @{}
    foreach ($l in $Doc.Layers) {
        $root = Get-PsdLayerRoot $l
        if ($null -ne $root) { Add-PsdOpenIfs $root $Doc $out $seen }
        foreach ($kind in 'Merge', 'Include') {
            foreach ($a in (Get-PsdActiveEntries $l.File $kind $Doc)) {
                $ref = $a.Entry.Ref
                if ($null -ne $ref -and -not $Doc.Paths.ContainsKey($ref.Id) -and -not $seen.ContainsKey($ref.Id)) {
                    $seen[$ref.Id] = $true
                    $out.Add((New-PsdOpenItem 'Path' $ref.Id $ref))
                }
            }
        }
    }
    , $out
}

# Adds the key paths an expression reads to Reads, and what the values there read in turn. name:: and env: are left
# out: no decision here can change them.
function Add-PsdExprReads {
    param($Expr, $Tree, $Reads, $Seen)
    foreach ($op in $Expr.Ops) {
        if ($op.T -ne 'Path' -or $op.Env -or $op.Ns -or $op.Builtin) { continue }
        $keys = New-PsdList
        foreach ($s in $op.Segs) {
            if ($s.IsIndex) { break }
            $keys.Add($s.Key)
        }
        if ($keys.Count -eq 0) { continue }
        $Reads[($keys -join '.').ToLowerInvariant()] = $op.Segs
        Add-PsdNodeReads (Get-PsdTreeNode $Tree $op.Segs) $Tree $Reads $Seen
    }
    foreach ($f in $Expr.Filters) { foreach ($a in $f.Args) { Add-PsdExprReads $a $Tree $Reads $Seen } }
}

function Add-PsdNodeReads {
    param($Node, $Tree, $Reads, $Seen)
    if ($null -eq $Node -or $Seen.ContainsKey($Node.Id)) { return }
    $Seen[$Node.Id] = $true
    switch ($Node.K) {
        'T' { foreach ($p in $Node.Parts) { if ($p -isnot [string]) { Add-PsdExprReads $p.Expr $Tree $Reads $Seen } } }
        'O' { Add-PsdNodeReads $Node.Base $Tree $Reads $Seen; Add-PsdNodeReads $Node.Arg $Tree $Reads $Seen }
        'M' { foreach ($k in $Node.V.PSBase.Keys) { Add-PsdNodeReads $Node.V[$k] $Tree $Reads $Seen } }
        'L' { foreach ($x in $Node.V) { Add-PsdNodeReads $x $Tree $Reads $Seen } }
    }
}

function Add-PsdCondReads {
    param($Cond, $Tree, $Reads, $Seen)
    switch ($Cond.T) {
        { $_ -in 'Or', 'And' } { Add-PsdCondReads $Cond.L $Tree $Reads $Seen; Add-PsdCondReads $Cond.R $Tree $Reads $Seen }
        'Not' { Add-PsdCondReads $Cond.X $Tree $Reads $Seen }
        'Truth' { if ($Cond.X.T -ne 'Lit') { Add-PsdExprReads $Cond.X.Expr $Tree $Reads $Seen } }
        'Cmp' { foreach ($x in $Cond.L, $Cond.R) { if ($x.T -ne 'Lit') { Add-PsdExprReads $x.Expr $Tree $Reads $Seen } } }
    }
}

# Adds the key paths a map writes to Out, with the !if in it.
function Add-PsdMapWrites {
    param($Map, [string] $Prefix, $Out)
    foreach ($k in $Map.V.PSBase.Keys) {
        $path = "$Prefix$k".ToLowerInvariant()
        $v = $Map.V[$k]
        if ($v.K -eq 'M' -and ($v.V.PSBase.Count -or $v.Ops.Count -or $v.Ifs.Count)) { Add-PsdMapWrites $v "$path." $Out }
        else { $Out[$path] = $true }
    }
    foreach ($op in $Map.Ops) { $Out["$Prefix$($op.Key)".ToLowerInvariant()] = $true }
    foreach ($if in $Map.Ifs) { Add-PsdMapWrites $if.Body $Prefix $Out }
}

# The first key path of Reads that Writes touches: the same key, or one inside the other. $null when there is none.
function Find-PsdKeyOverlap {
    param($Reads, $Writes)
    foreach ($r in $Reads.PSBase.Keys) {
        foreach ($w in $Writes.PSBase.Keys) {
            if ($r -eq $w -or $r.StartsWith("$w.", [StringComparison]::Ordinal) -or $w.StartsWith("$r.", [StringComparison]::Ordinal)) { return $r }
        }
    }
    $null
}

function Get-PsdItemResult {
    param($Item, $Partial, $Doc)
    if ($Item.Kind -eq 'If') {
        return [bool](Test-PsdCondition $Item.Node.Cond @{ Doc = $Partial; Node = $Item.Node; InCond = $true; Final = $Doc })
    }
    $value = Get-PsdNodeValue $Item.Node $Partial
    if ($value -is [string] -and $value.Length -gt 0) { return $value }
    if ($Doc.Ctx.Errors.Count -eq 0) { Add-PsdNodeError $Doc.Ctx 'PSD206' "this path is $(Get-PsdKindText $value), but it has to be text." $Item.Node }
    $null
}

function Add-PsdDependencyError {
    param($Open, $Ctx)
    $extra = New-PsdList
    foreach ($i in $Open) {
        $n = $i.Node
        $text = if ($i.Kind -eq 'If') { $n.Raw } else { $n.Text }
        $extra.Add("$($n.File.Name + $n.File.Ext), line $($n.Line): $text")
    }
    $extra.Add('')
    Add-PsdNodeError $Ctx 'PSD404' 'these conditions read what the others write, so there is no order to decide them in.' $Open[0].Node `
        -Extra $extra -Hint @('Give one of the keys a value outside of the !if, or join the conditions.')
}

# A file loaded after a decision can change what it read: then the decision was wrong, and that is an error.
function Test-PsdLateFiles {
    param($Doc, $Decided, $Files)
    if ($Decided.Count -eq 0) { return }
    $final = $null
    foreach ($item in $Decided) {
        foreach ($f in $Files.Values) {
            if ($f.Round -lt $item.Round -or @($f.Via) -contains $item.Id) { continue }
            $key = Find-PsdKeyOverlap $item.Reads $f.Writes
            if ($null -eq $key -or $null -ne (Find-PsdKeyOverlap $item.Reads $item.Writes)) { continue }
            if ($null -eq $final) { $final = New-PsdPartialDoc $Doc }
            $now = Get-PsdItemResult $item $final $Doc
            if ($now -ne $item.Result) {
                Add-PsdNodeError $Doc.Ctx 'PSD405' "this was decided as '$($item.Result)', but $($f.Name) was loaded after that and sets $key, which makes it '$now'." $item.Node `
                    -Hint @('Set the key in a file that is always loaded, or make the conditions not depend on it.')
            }
            break
        }
    }
}

# What Get-PsdLoadPlan returns for a document.
function Get-PsdPlanResult {
    param($Doc)
    $steps = foreach ($item in $Doc.Steps) {
        $reads = [ordered]@{}
        foreach ($key in @($item.Reads.PSBase.Keys | Sort-Object)) {
            $cur = Get-PsdTreeNode $item.Partial.Tree $item.Reads[$key]
            $reads[$key] = if ($null -eq $cur) { $null } else { Get-PsdNodeValue $cur $item.Partial }
        }
        $node = $item.Node
        [pscustomobject]@{
            Round = $item.Round
            Kind = $item.Kind
            File = $node.File.Path
            Line = $node.Line
            Text = if ($item.Kind -eq 'If') { $node.Raw } else { $node.Text }
            Result = $item.Result
            Reads = $reads
        }
    }
    [pscustomobject]@{
        Files = @($Doc.Layers | ForEach-Object { $_.File.Path })
        Steps = @($steps)
    }
}

# Decides everything open, loading files as they turn up, and leaves the final layers on the document.
function Resolve-PsdDocFiles {
    param($Doc, $Sources)
    Update-PsdDocFiles $Doc $Sources
    $decided = New-PsdList
    $files = @{}
    $round = 0
    while ($true) {
        foreach ($l in $Doc.Layers) {
            if ($files.ContainsKey($l.File.Key) -or $null -eq $l.File.Root) { continue }
            $writes = @{}
            Add-PsdMapWrites $l.File.Root '' $writes
            $files[$l.File.Key] = @{ Name = $l.File.Name + $l.File.Ext; Round = $round; Via = $l.Via; Writes = $writes }
        }
        $open = Get-PsdOpenItems $Doc
        if ($open.Count -eq 0) { break }
        $round++
        $partial = New-PsdPartialDoc $Doc
        foreach ($item in $open) {
            $seen = @{}
            if ($item.Kind -eq 'If') {
                Add-PsdCondReads $item.Node.Cond $partial.Tree $item.Reads $seen
                Add-PsdMapWrites $item.Node.Body '' $item.Writes
                $item.Loads = Test-PsdMapLoads $item.Node.Body
            }
            else { Add-PsdNodeReads $item.Node $partial.Tree $item.Reads $seen }
        }
        $ready = New-PsdList
        foreach ($item in $open) {
            $blocked = $false
            foreach ($other in $open) {
                if ($other.Id -ne $item.Id -and $null -ne (Find-PsdKeyOverlap $item.Reads $other.Writes)) { $blocked = $true; break }
            }
            if (-not $blocked) { $ready.Add($item) }
        }
        if ($ready.Count -eq 0) {
            Add-PsdDependencyError $open $Doc.Ctx
            break
        }
        # what loads files goes first: those files can set what the other conditions read
        $loading = New-PsdList
        foreach ($item in $ready) { if ($item.Loads) { $loading.Add($item) } }
        if ($loading.Count) { $ready = $loading }
        foreach ($item in $ready) {
            $item.Round = $round
            $item.Partial = $partial
            $item.Result = Get-PsdItemResult $item $partial $Doc
            if ($item.Kind -eq 'If') { $Doc.Decisions[$item.Id] = $item.Result } else { $Doc.Paths[$item.Id] = $item.Result }
            $decided.Add($item)
        }
        Update-PsdDocFiles $Doc $Sources
    }
    $Doc.Settled = $true
    Update-PsdDocFiles $Doc $Sources
    Test-PsdLateFiles $Doc $decided $files
    $Doc.Steps = $decided
}
