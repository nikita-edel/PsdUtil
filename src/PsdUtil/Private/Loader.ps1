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
        [Array]::Sort($files, [StringComparer]::OrdinalIgnoreCase)
        foreach ($f in $files) { $out.Add([IO.Path]::GetFullPath($f)) }
        return , $out
    }
    $out.Add([IO.Path]::GetFullPath($full))
    , $out
}

function New-PsdLayer {
    param($File, $Only = $null)
    @{ File = $File; Only = $Only; Root = $null; Via = $null }
}

function Test-PsdOnStack {
    param($Stack, [string] $Key)
    foreach ($s in $Stack) { if ($s.Key -eq $Key) { return $true } }
    $false
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
    foreach ($if in $Root.Ifs) { foreach ($k in (Get-PsdTopKeys $if.Body)) { $keys.Add($k) } }
    , $keys
}

# The layers of a file's chain, bottom first: every !merge that counts by now, then the file itself.
function Get-PsdLayers {
    param($File, $Ctx, $Doc, $Stack)
    $result = New-PsdList
    if ($null -eq $Stack) { $Stack = New-PsdList }
    $Stack.Add($File)
    foreach ($active in (Get-PsdActiveEntries $File 'Merge' $Doc)) {
        $m = $active.Entry
        $path = Get-PsdEntryPath $m $Doc
        if (-not $path) { continue }
        foreach ($p in (Resolve-PsdPaths $path $File $m.Node $Ctx)) {
            if (Test-PsdOnStack $Stack (Get-PsdPathKey $p)) {
                Add-PsdNodeError $Ctx 'PSD201' 'these files merge each other in a circle.' $m.Node -Extra @((Get-PsdChainText $Stack $p), '') -Hint @("Remove one of the '!merge' lines.")
                continue
            }
            $sub = Read-PsdFile $p $Ctx $m.Node 'PSD200'
            if ($null -eq $sub -or $null -eq $sub.Root) { continue }
            $subLayers = Get-PsdLayers $sub $Ctx $Doc $Stack
            if ($null -ne $active.Via) { foreach ($l in $subLayers) { if ($null -eq $l.Via) { $l.Via = $active.Via } } }
            if ($m.Only) {
                $have = New-PsdList
                foreach ($l in $subLayers) { foreach ($x in (Get-PsdTopKeys $l.File.Root)) { $have.Add($x) } }
                # before everything is decided, a key can still come from a file that isn't loaded yet
                foreach ($want in $m.Only) {
                    if ($Doc.Settled -and $have -inotcontains $want) {
                        Add-PsdNodeError $Ctx 'PSD207' "'$want' isn't a key in $($sub.Name + $sub.Ext)." $m.Node -Hint @((Get-PsdDidYouMean $want $have))
                    }
                }
                foreach ($l in $subLayers) {
                    $keys = $m.Only
                    if ($l.Only) {
                        $keys = New-PsdList
                        foreach ($x in $l.Only) { if ($m.Only -icontains $x) { $keys.Add($x) } }
                    }
                    $layer = New-PsdLayer $l.File $keys
                    $layer.Via = $l.Via
                    $result.Add($layer)
                }
            }
            else { foreach ($l in $subLayers) { $result.Add($l) } }
        }
    }
    $result.Add((New-PsdLayer $File))
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
        $copy = New-PsdLayer $l.File
        $copy.Via = $l.Via
        if ($l.Only) { $copy.Only = $l.Only.GetRange(0, $l.Only.Count) }
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
        # the analysis step: true or false by !if, the text by path with a reference, and what it decided in order
        Decisions = @{}
        Paths     = @{}
        Steps     = $null
        Settled   = $false
        Prov      = $null
        Tree      = $null
        Final     = $null
        AllTree   = $null
        # schema rule of the top map, for Merge; -Merge as @{ Pattern; Op }
        Rules     = $null
        Defaults  = $null
    }
}

# Adds a name to Table (the document's Ns or Inc) as Value, unless it can't be used. Target is the file behind it.
function Register-PsdNs {
    param($Doc, $Table, [string] $Ns, $Target, $Value, $Node, $Ctx)
    if ($Ns -ieq 'this') {
        if ($Node) { Add-PsdNodeError $Ctx 'PSD204' "a file can't be called 'this', because this:: always means the file it's written in." $Node -Hint @("Rename it, or give it a name with '!name'.") }
        else { Add-PsdError $Ctx 'PSD204' "a file can't be called 'this', because this:: always means the file it's written in." -File $Target -Hint @("Give it a name with '!name' = '...'") }
        return
    }
    foreach ($taken in @($Doc.Ns, $Doc.Inc)) {
        if ($taken.ContainsKey($Ns)) {
            $old = $taken[$Ns]
            $oldKey = if ($old.ContainsKey('Entry')) { $old.Entry.Key } else { $old.Key }
            if ($oldKey -ne $Target.Key) {
                Add-PsdNodeError $Ctx 'PSD203' "two different files or maps are both called '$Ns', so $Ns:: can't tell them apart." $Node -Hint @("Give one of them its own name with '!name' = '...'")
            }
            return
        }
    }
    $Table[$Ns] = $Value
}

function Get-PsdIncludedDoc {
    param($File, $Ctx, $Node)
    if ($Ctx.Docs.ContainsKey($File.Key)) { return $Ctx.Docs[$File.Key] }
    if (Test-PsdOnStack $Ctx.DocStack $File.Key) {
        Add-PsdNodeError $Ctx 'PSD201' 'these files include each other in a circle.' $Node -Extra @((Get-PsdChainText $Ctx.DocStack $File.Path), '') -Hint @("Remove one of the '!include' lines.")
        return $null
    }
    $doc = New-PsdDoc $File @(@{ File = $File }) $Ctx
    $Ctx.Docs[$File.Key] = $doc
    $doc
}

# Maps from the caller, readable as name::Key like an included file.
function Add-PsdMapIncludes {
    param($Doc, $Include, $Ctx)
    foreach ($key in @($Include.PSBase.Keys)) {
        $name = [string]$key
        $value = $Include[$key]
        if ($name -ieq 'this') {
            Add-PsdError $Ctx 'PSD204' "'this' can't be a name in -Include, because this:: always means the file it's written in."
            continue
        }
        if (-not $script:PsdRxFileName.IsMatch($name)) {
            Add-PsdError $Ctx 'PSD206' "'$name' can't be a name in -Include. Names can't have spaces or signs like :, @ or !."
            continue
        }
        if (-not (Test-PsdMapLike $value)) {
            Add-PsdError $Ctx 'PSD206' "-Include needs a map for '$name', but it's $(Get-PsdKindText $value)."
            continue
        }
        $f = New-PsdSyntheticFile $name $Doc.Entry.Dir
        $f.Label = $name
        $f.Named = $true
        $f.Root = ConvertFrom-PsdObject $value $f $Ctx ''
        $idoc = New-PsdDoc $f @(@{ Layer = (New-PsdLayer $f) }) $Ctx
        $Ctx.Docs[$f.Key] = $idoc
        Register-PsdNs $Doc $Doc.Inc $name $f $idoc $null $Ctx
    }
}

# Sources, in order: @{ File } for a file with its chain, @{ Layer } for one layer as it is.
# Rules and Defaults give keys without an operator a default one, see Get-PsdDefaultOp. Included files get none.
function New-PsdDoc {
    param($Entry, $Sources, $Ctx, [bool] $Prov = $false, $Include = $null, $Rules = $null, $Defaults = $null)
    $Ctx.DocStack.Add($Entry)
    $doc = New-PsdDocObject $Entry $null $Ctx
    $doc.Rules = $Rules
    $doc.Defaults = $Defaults
    if ($Prov) { $doc.Prov = @{} }
    if ($null -ne $Include) { Add-PsdMapIncludes $doc $Include $Ctx }
    Resolve-PsdDocFiles $doc $Sources
    $Ctx.DocStack.RemoveAt($Ctx.DocStack.Count - 1)
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
    $n = New-PsdMapNode $Root.File $null $Root.Path
    Copy-PsdLocation $Root $n
    foreach ($k in $Root.V.PSBase.Keys) { if ($Keys -icontains $k) { $n.V[$k] = $Root.V[$k] } }
    foreach ($op in $Root.Ops) { if ($Keys -icontains $op.Key) { $n.Ops.Add($op) } }
    foreach ($if in $Root.Ifs) {
        $copy = $if.Clone()
        $copy.Body = Select-PsdKeys $if.Body $Keys
        $n.Ifs.Add($copy)
    }
    $n
}

function Merge-PsdLayers {
    param($Doc, [bool] $Quiet, [string] $Mode = $null)
    if (-not $Mode) { $Mode = $Doc.Mode }
    $m = @{ Doc = $Doc; Quiet = $Quiet; Mode = $Mode; Prov = $null; Ctx = $Doc.Ctx; Defaults = $Doc.Defaults }
    if (-not $Quiet) { $m.Prov = $Doc.Prov }
    $acc = $null
    foreach ($l in $Doc.Layers) {
        $root = Get-PsdLayerRoot $l
        if ($null -eq $root) { continue }
        $acc = Merge-PsdMap $acc $root $m '' $Doc.Rules
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
            $m = @{ Doc = $Doc; Quiet = $true; Mode = $Doc.Mode; Prov = $null; Ctx = $Doc.Ctx; Defaults = $null }
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
    param($Entry, $Ctx, $Override = $null, [switch] $Prov, $Include = $null, $Rules = $null, $Defaults = $null)
    $sources = New-PsdList
    $sources.Add(@{ File = $Entry })
    if ($null -ne $Override) {
        if (-not ($Override -is [System.Collections.IDictionary] -or $null -ne (Get-PsdKeptMap $Override))) {
            Add-PsdError $Ctx 'PSD206' "-Override needs a map, or a generated class made from one, but it's $(Get-PsdKindText $Override)."
            $Override = @{}
        }
        $of = New-PsdSyntheticFile 'override' $Entry.Dir
        $of.Root = ConvertFrom-PsdObject $Override $of $Ctx ''
        $sources.Add(@{ Layer = (New-PsdLayer $of) })
    }
    New-PsdDoc $Entry $sources $Ctx $Prov.IsPresent $Include $Rules $Defaults
}
