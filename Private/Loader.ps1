# Follows !merge and !include, expands globs, builds documents.

# Turns a path written in a file into full paths. Wildcards work in the file name.
function Resolve-PsdPaths {
    param([string] $Pattern, $From, $Node, $Ctx)
    $out = New-PsdList
    if ($Pattern -match '^[A-Za-z][A-Za-z0-9+.\-]*://') {
        Add-PsdNodeError $Ctx 'PSD208' "'$Pattern' is a URL. Only local files can be merged or included." $Node
        return , $out
    }
    $full = $Pattern
    if (-not [IO.Path]::IsPathRooted($full)) { $full = [IO.Path]::Combine($From.Dir, $full) }
    $leaf = [IO.Path]::GetFileName($full)
    if ($leaf.IndexOf('*') -ge 0 -or $leaf.IndexOf('?') -ge 0) {
        # .NET Framework rejects wildcards in GetFullPath, so only the folder is resolved.
        $dir = [IO.Path]::GetFullPath($full.Substring(0, $full.Length - $leaf.Length))
        if ($dir.IndexOf('*') -ge 0 -or $dir.IndexOf('?') -ge 0) {
            Add-PsdNodeError $Ctx 'PSD206' 'wildcards only work in the file name, not in folder names.' $Node
            return , $out
        }
        $files = @()
        if ([IO.Directory]::Exists($dir)) {
            $wc = New-Object System.Management.Automation.WildcardPattern $leaf, ([System.Management.Automation.WildcardOptions]::IgnoreCase)
            $files = @([IO.Directory]::GetFiles($dir) | Where-Object { $wc.IsMatch([IO.Path]::GetFileName($_)) })
        }
        if ($files.Count -eq 0) {
            Add-PsdNodeError $Ctx 'PSD202' "nothing matches '$Pattern'." $Node -Hint @("Looked in $dir")
            return , $out
        }
        $sorted = New-PsdList
        foreach ($f in $files) { $sorted.Add($f) }
        $sorted.Sort([Comparison[object]] { param($a, $b) [string]::Compare([string]$a, [string]$b, [StringComparison]::OrdinalIgnoreCase) })
        foreach ($f in $sorted) { $out.Add([IO.Path]::GetFullPath($f)) }
        return , $out
    }
    $out.Add([IO.Path]::GetFullPath($full))
    , $out
}

function Get-PsdChainText {
    param($Stack, [string] $Last)
    $names = New-PsdList
    $startIdx = 0
    for ($i = 0; $i -lt $Stack.Count; $i++) { if ($Stack[$i].Key -eq (Get-PsdPathKey $Last)) { $startIdx = $i; break } }
    for ($i = $startIdx; $i -lt $Stack.Count; $i++) { $names.Add($Stack[$i].Name + $Stack[$i].Ext) }
    $names.Add([IO.Path]::GetFileName($Last))
    $names -join ' -> '
}

function Get-PsdTopKeys {
    param($Root)
    $keys = New-PsdList
    if ($null -eq $Root) { return , $keys }
    foreach ($k in $Root.V.PSBase.Keys) { $keys.Add($k) }
    foreach ($op in $Root.Ops) { $keys.Add($op.Key) }
    foreach ($if in $Root.Ifs) { foreach ($k in $if.Body.V.PSBase.Keys) { $keys.Add($k) }; foreach ($op in $if.Body.Ops) { $keys.Add($op.Key) } }
    , $keys
}

# The layers of a file's chain, bottom first: every !merge, then the file itself.
function Get-PsdLayers {
    param($File, $Ctx, $Stack)
    $result = New-PsdList
    if ($null -eq $Stack) { $Stack = New-PsdList }
    $Stack.Add($File)
    foreach ($m in $File.Merge) {
        foreach ($p in (Resolve-PsdPaths $m.Path $File $m.Node $Ctx)) {
            $k = Get-PsdPathKey $p
            $loop = $false
            foreach ($s in $Stack) { if ($s.Key -eq $k) { $loop = $true } }
            if ($loop) {
                Add-PsdNodeError $Ctx 'PSD201' 'these files merge each other in a circle.' $m.Node -Extra @((Get-PsdChainText $Stack $p), '') -Hint @("Remove one of the '!merge' lines.")
                continue
            }
            $sub = Read-PsdFile $p $Ctx $m.Node 'PSD200'
            if ($null -eq $sub -or $null -eq $sub.Root) { continue }
            $subLayers = Get-PsdLayers $sub $Ctx $Stack
            if ($m.Only) {
                $have = New-PsdList
                foreach ($l in $subLayers) { foreach ($x in (Get-PsdTopKeys $l.File.Root)) { $have.Add($x) } }
                foreach ($want in $m.Only) {
                    $found = $false
                    foreach ($h in $have) { if ($h -ieq $want) { $found = $true; break } }
                    if (-not $found) {
                        Add-PsdNodeError $Ctx 'PSD207' "'$want' isn't a key in $($sub.Name + $sub.Ext)." $m.Node -Hint @((Get-PsdDidYouMean $want $have))
                    }
                }
                foreach ($l in $subLayers) {
                    $keys = $m.Only
                    if ($l.Only) {
                        $keys = New-PsdList
                        foreach ($x in $l.Only) { foreach ($y in $m.Only) { if ($x -ieq $y) { $keys.Add($x) } } }
                    }
                    $result.Add(@{ File = $l.File; Only = $keys; Root = $null })
                }
            }
            else { foreach ($l in $subLayers) { $result.Add($l) } }
        }
    }
    $result.Add(@{ File = $File; Only = $null; Root = $null })
    $Stack.RemoveAt($Stack.Count - 1)

    # A file reached twice is used once, where it first appears.
    $seen = @{}
    $out = New-PsdList
    foreach ($l in $result) {
        if ($seen.ContainsKey($l.File.Key)) {
            $first = $seen[$l.File.Key]
            if ($null -eq $l.Only) { $first.Only = $null }
            elseif ($first.Only) { foreach ($x in $l.Only) { $first.Only.Add($x) } }
            continue
        }
        $copy = @{ File = $l.File; Only = $null; Root = $null }
        if ($l.Only) { $copy.Only = New-PsdList; foreach ($x in $l.Only) { $copy.Only.Add($x) } }
        $seen[$l.File.Key] = $copy
        $out.Add($copy)
    }
    , $out
}

function New-PsdDocObject {
    param($Entry, $Layers, $Ctx)
    @{
        Entry     = $Entry
        Layers    = $Layers
        Ns        = @{}
        Inc       = @{}
        Ctx       = $Ctx
        Mode      = 'Doc'
        Cache     = @{}
        ResSet    = @{}
        ResList   = New-PsdList
        RefDepth  = 0
        Own       = @{}
        Decisions = @{}
        Prov      = $null
        Tree      = $null
        Prelim    = $null
        Final     = $null
        AllTree   = $null
    }
}

function Register-PsdNs {
    param($Doc, [string] $Ns, $Target, [string] $TargetKey, $Node, $Ctx)
    if ($Ns -ieq 'this') {
        if ($Node) { Add-PsdNodeError $Ctx 'PSD204' "a file can't be called 'this', because this:: always means the file it's written in." $Node -Hint @("Rename it, or give it a name with '!name'.") }
        else { Add-PsdError $Ctx 'PSD204' "a file can't be called 'this', because this:: always means the file it's written in." -File $Target -Hint @("Give it a name with '!name' = '...'") }
        return
    }
    foreach ($table in @($Doc.Ns, $Doc.Inc)) {
        if ($table.ContainsKey($Ns)) {
            $old = $table[$Ns]
            $oldKey = if ($old.ContainsKey('Entry')) { $old.Entry.Key } else { $old.Key }
            if ($oldKey -ne $TargetKey) {
                $msg = "two different files are both called '$Ns', so $Ns:: can't tell them apart."
                if ($Node) { Add-PsdNodeError $Ctx 'PSD203' $msg $Node -Hint @("Give one of them its own name with '!name' = '...'") }
                else { Add-PsdError $Ctx 'PSD203' $msg -Hint @("Give one of them its own name with '!name' = '...'") }
            }
            return
        }
    }
}

function Get-PsdIncludedDoc {
    param($File, $Ctx, $Node)
    if ($Ctx.Docs.ContainsKey($File.Key)) { return $Ctx.Docs[$File.Key] }
    foreach ($s in $Ctx.DocStack) {
        if ($s.Key -eq $File.Key) {
            Add-PsdNodeError $Ctx 'PSD201' 'these files include each other in a circle.' $Node -Extra @((Get-PsdChainText $Ctx.DocStack $File.Path), '') -Hint @("Remove one of the '!include' lines.")
            return $null
        }
    }
    $layers = Get-PsdLayers $File $Ctx
    $doc = New-PsdDoc $File $layers $Ctx
    $Ctx.Docs[$File.Key] = $doc
    $doc
}

function New-PsdDoc {
    param($Entry, $Layers, $Ctx, [bool] $Prov = $false)
    $Ctx.DocStack.Add($Entry)
    $doc = New-PsdDocObject $Entry $Layers $Ctx
    if ($Prov) { $doc.Prov = @{} }
    foreach ($l in $Layers) {
        $f = $l.File
        if ($f.Synthetic) { continue }
        Register-PsdNs $doc $f.Ns $f $f.Key $null $Ctx
        if (-not $doc.Ns.ContainsKey($f.Ns) -and -not $doc.Inc.ContainsKey($f.Ns) -and $f.Ns -ine 'this') { $doc.Ns[$f.Ns] = $f }
    }
    foreach ($l in $Layers) {
        foreach ($inc in $l.File.Include) {
            foreach ($p in (Resolve-PsdPaths $inc.Path $l.File $inc.Node $Ctx)) {
                $f = Read-PsdFile $p $Ctx $inc.Node 'PSD200'
                if ($null -eq $f -or $null -eq $f.Root) { continue }
                $idoc = Get-PsdIncludedDoc $f $Ctx $inc.Node
                if ($null -eq $idoc) { continue }
                Register-PsdNs $doc $f.Ns $f $f.Key $inc.Node $Ctx
                if (-not $doc.Ns.ContainsKey($f.Ns) -and -not $doc.Inc.ContainsKey($f.Ns) -and $f.Ns -ine 'this') { $doc.Inc[$f.Ns] = $idoc }
            }
        }
    }
    $Ctx.DocStack.RemoveAt($Ctx.DocStack.Count - 1)

    # Conditions are decided against everything except the !if bodies.
    $pre = New-PsdDocObject $Entry $Layers $Ctx
    $pre.Ns = $doc.Ns
    $pre.Inc = $doc.Inc
    $pre.Mode = 'None'
    $pre.Final = $doc
    $pre.Tree = Merge-PsdLayers $pre $true
    $doc.Prelim = $pre
    $doc.Tree = Merge-PsdLayers $doc $false
    $doc
}

function Get-PsdLayerRoot {
    param($Layer)
    if ($null -ne $Layer.Root) { return $Layer.Root }
    $root = $Layer.File.Root
    if ($null -eq $root) { return $null }
    if ($Layer.Only) { $root = Select-PsdKeys $root $Layer.Only }
    $Layer.Root = $root
    $root
}

function Select-PsdKeys {
    param($Root, $Keys)
    $test = { param($k) foreach ($x in $Keys) { if ($x -ieq $k) { return $true } }; $false }
    $n = New-PsdMapNode $Root.File $null $Root.Path
    Copy-PsdLocation $Root $n
    foreach ($k in $Root.V.PSBase.Keys) { if (& $test $k) { $n.V[$k] = $Root.V[$k] } }
    foreach ($op in $Root.Ops) { if (& $test $op.Key) { $n.Ops.Add($op) } }
    foreach ($if in $Root.Ifs) {
        $copy = @{}
        foreach ($k in $if.PSBase.Keys) { $copy[$k] = $if[$k] }
        $copy.Body = Select-PsdKeys $if.Body $Keys
        $n.Ifs.Add($copy)
    }
    $n
}

function Merge-PsdLayers {
    param($Doc, [bool] $Quiet, [string] $Mode = $null)
    if (-not $Mode) { $Mode = $Doc.Mode }
    $m = @{ Doc = $Doc; Quiet = $Quiet; Mode = $Mode; Prov = $null; Ctx = $Doc.Ctx }
    if (-not $Quiet) { $m.Prov = $Doc.Prov }
    $acc = $null
    foreach ($l in $Doc.Layers) {
        $root = Get-PsdLayerRoot $l
        if ($null -eq $root) { continue }
        $acc = Merge-PsdMap $acc $root $m ''
    }
    if ($null -eq $acc) { $acc = New-PsdMapNode $Doc.Entry $null '' }
    $acc
}

# A file on its own, before merging: what this:: and name:: read.
function Get-PsdOwnTree {
    param($Doc, $File)
    if ($Doc.Own.ContainsKey($File.Key)) { return $Doc.Own[$File.Key] }
    $tree = New-PsdMapNode $File $null ''
    foreach ($l in $Doc.Layers) {
        if ($l.File.Key -eq $File.Key) {
            $m = @{ Doc = $Doc; Quiet = $true; Mode = $Doc.Mode; Prov = $null; Ctx = $Doc.Ctx }
            $tree = Merge-PsdMap $null $l.File.Root $m ''
            break
        }
    }
    $Doc.Own[$File.Key] = $tree
    $tree
}

function Get-PsdAllTree {
    param($Doc)
    if ($null -eq $Doc.AllTree) { $Doc.AllTree = Merge-PsdLayers $Doc $true 'All' }
    $Doc.AllTree
}

# Builds the document for a file, with an optional extra layer on top.
function New-PsdFileDoc {
    param($Entry, $Ctx, $Override = $null, [switch] $Prov)
    $layers = Get-PsdLayers $Entry $Ctx
    if ($null -ne $Override) {
        $of = New-PsdSyntheticFile 'override' $Entry.Dir
        $of.Root = ConvertFrom-PsdObject $Override $of $Ctx ''
        $layers.Add(@{ File = $of; Only = $null; Root = $null })
    }
    New-PsdDoc $Entry $layers $Ctx $Prov.IsPresent
}
