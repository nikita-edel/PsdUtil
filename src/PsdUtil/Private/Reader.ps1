using namespace System.Management.Automation.Language

# Turns files (or plain objects) into a tree of values, without running any code.

$script:PsdRxOp = New-Object regex '^(.*\S) (\+=|=\+|\|=|-=|:=)$'
$script:PsdRxNearOp = New-Object regex '^(.*\S) ([-+=|:]{1,3})$'
$script:PsdRxIndexKey = New-Object regex '^(.*\S)\[(-?[0-9]+)\]$'
$script:PsdRxValueKey = New-Object regex '^(.*\S)\[(?:''((?:[^'']|'''')*)''|"((?:[^"]|"")*)")\]$'
$script:PsdDirectives = @('!merge', '!include', '!name', '!schema', '!types')
$script:PsdOperators = @('+=', '=+', '|=', '-=', ':=')

function New-PsdFileRec {
    param([string] $Full, [string] $Text)
    $leaf = [IO.Path]::GetFileName($Full)
    $ext = [IO.Path]::GetExtension($leaf)
    $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $lines = $null
    if ($null -ne $Text) { $lines = $Text -split '\r?\n' }
    @{
        Id        = New-PsdId
        Path      = $Full
        Key       = Get-PsdPathKey $Full
        Name      = $name
        Ext       = $ext
        Ns        = $name
        Dir       = [IO.Path]::GetDirectoryName($Full)
        Lines     = $lines
        Root      = $null
        Merge     = New-PsdList
        Include   = New-PsdList
        Schema    = $null
        Types     = New-PsdList
        Synthetic = $false
        Named     = $false
        Label     = $null
    }
}

function New-PsdNode {
    param([string] $Kind, $Value, $File, $Ast, [string] $Path)
    $n = @{
        Id = New-PsdId; K = $Kind; V = $Value; File = $File; Line = 0; Col = 0; Text = $null; Path = $Path
        Parts = $null; Ops = $null; Ifs = $null; Base = $null; Op = $null; Arg = $null; Index = $null; Match = $null; Offset = 0
        KeyLine = 0; KeyCol = 0; KeyLen = 0
    }
    if ($Ast) {
        $n.Line = $Ast.Extent.StartLineNumber
        $n.Col = $Ast.Extent.StartColumnNumber
        $n.Text = $Ast.Extent.Text
    }
    $n
}

# Strict UTF-8: bytes that aren't UTF-8 give $null instead of being replaced. A BOM is dropped.
function ConvertFrom-PsdUtf8 {
    param([byte[]] $Bytes)
    try { $text = (New-Object System.Text.UTF8Encoding $false, $true).GetString($Bytes) }
    catch { return $null }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { return $text.Substring(1) }
    $text
}

# Reports nesting past MaxDepth and returns the node that stands in for the value there.
function New-PsdTooDeepNode {
    param($File, $Ast, [string] $Path, $Ctx)
    $deep = New-PsdNode 'S' $null $File $Ast $Path
    Add-PsdLimitError $Ctx 'MaxDepth' "by nesting at $Path" $deep
    $deep
}

function New-PsdMapNode {
    param($File, $Ast, [string] $Path)
    $n = New-PsdNode 'M' ([ordered]@{}) $File $Ast $Path
    $n.Ops = New-PsdList
    $n.Ifs = New-PsdList
    # the '!merge' and '!include' of the body of an !if
    $n.Merge = New-PsdList
    $n.Include = New-PsdList
    $n
}

function Copy-PsdLocation {
    param($From, $To)
    $To.File = $From.File; $To.Line = $From.Line; $To.Col = $From.Col; $To.Text = $From.Text
    $To.KeyLine = $From.KeyLine; $To.KeyCol = $From.KeyCol; $To.KeyLen = $From.KeyLen
}

# --- Positions ----------------------------------------------------------------

# Maps an index in a string's value to a line and column in the file, using the
# text of the string as written (quotes, doubled quotes, escapes).
function Get-PsdSourcePos {
    param($Node, [int] $ValueIndex)
    $text = $Node.Text
    if (-not $text) { return @{ Line = $Node.Line; Col = $Node.Col } }
    $pos = 0
    if ($text.StartsWith("@'") -or $text.StartsWith('@"')) {
        $pos = $text.IndexOf("`n") + 1
        $pos += $ValueIndex
    }
    elseif ("'`"".IndexOf($text[0]) -ge 0 -or ([int]$text[0] -ge 0x2018 -and [int]$text[0] -le 0x201E)) {
        $double = ($text[0] -eq '"') -or ([int]$text[0] -ge 0x201C)
        $pos = 1
        $vi = 0
        while ($vi -lt $ValueIndex -and $pos -lt $text.Length) {
            $c = $text[$pos]
            if ($double -and $c -eq '`') { $pos += 2 }
            elseif ($pos + 1 -lt $text.Length -and $text[$pos + 1] -eq $c -and ("'`"".IndexOf($c) -ge 0)) { $pos += 2 }
            else { $pos++ }
            $vi++
        }
    }
    else { $pos = $ValueIndex }
    if ($pos -gt $text.Length) { $pos = $text.Length }
    $before = $text.Substring(0, $pos)
    $nl = $before.LastIndexOf("`n")
    if ($nl -lt 0) { return @{ Line = $Node.Line; Col = $Node.Col + $pos } }
    $lineNo = $Node.Line + ($before.Split("`n").Count - 1)
    @{ Line = $lineNo; Col = $pos - $nl }
}

function Get-PsdNodeLoc {
    param($Node, [int] $Start = -1, [int] $Length = 0)
    if ($null -eq $Node) { return @{ File = $null; Line = 0; Col = 0; Len = 0 } }
    if ($Start -lt 0) {
        $len = $Length
        if ($len -le 0 -and $Node.Text) { $len = ($Node.Text -split '\r?\n')[0].Length }
        return @{ File = $Node.File; Line = $Node.Line; Col = $Node.Col; Len = $len }
    }
    $p = Get-PsdSourcePos $Node ($Node.Offset + $Start)
    @{ File = $Node.File; Line = $p.Line; Col = $p.Col; Len = $Length }
}

function Add-PsdNodeError {
    param($Ctx, [string] $Code, [string] $Message, $Node, [int] $Start = -1, [int] $Length = 0, [string[]] $Hint = @(), [string[]] $Extra = @())
    $loc = Get-PsdNodeLoc $Node $Start $Length
    $key = $null
    if ($Node) { $key = $Node.Path }
    Add-PsdError $Ctx $Code $Message -File $loc.File -Line $loc.Line -Column $loc.Col -Length $loc.Len -Key $key -Hint $Hint -Extra $Extra
}

# An error at the first line of some parsed text.
function Add-PsdExtentError {
    param($Ctx, [string] $Code, [string] $Message, $File, $Extent)
    Add-PsdError $Ctx $Code $Message -File $File -Line $Extent.StartLineNumber -Column $Extent.StartColumnNumber -Length (($Extent.Text -split '\r?\n')[0].Length)
}

# An error at a key of a map.
function Add-PsdKeyError {
    param($Ctx, [string] $Code, [string] $Message, $KInfo, [string] $Key = $null, [string[]] $Hint = @())
    Add-PsdError $Ctx $Code $Message -File $KInfo.File -Line $KInfo.Line -Column $KInfo.Col -Length $KInfo.Len -Key $Key -Hint $Hint
}

# --- Reading files --------------------------------------------------------------

function Read-PsdFile {
    param([string] $Path, $Ctx, $From = $null, [string] $Code = 'PSD100')
    $full = [IO.Path]::GetFullPath($Path)
    $key = Get-PsdPathKey $full
    if ($Ctx.Files.ContainsKey($key)) { return $Ctx.Files[$key] }
    if (-not [IO.File]::Exists($full)) {
        Add-PsdNodeError $Ctx $Code "the file $full doesn't exist." $From
        return $null
    }
    if ($Ctx.Files.Count -ge $Ctx.Limits.MaxFiles) {
        Add-PsdLimitError $Ctx 'MaxFiles' "while loading $full"
        return $null
    }
    $ext = [IO.Path]::GetExtension($full)
    if ($ext -ine '.psd1' -and $null -ne $Ctx.Loader) { return (Read-PsdLoadedFile $full $Ctx $From) }
    if ($ext -ieq '.ps1') {
        Add-PsdNodeError $Ctx 'PSD108' "$full is a script, and PsdUtil runs no code." $From -Hint @('Pass -Loader { param($Path) & $Path } to read scripts, or write the file as .psd1.')
        return $null
    }
    $info = New-Object IO.FileInfo $full
    if ($info.Length -gt $Ctx.Limits.MaxFileSize) {
        Add-PsdLimitError $Ctx 'MaxFileSize' "by $full, which is $($info.Length) bytes"
        return $null
    }
    try { $bytes = [IO.File]::ReadAllBytes($full) }
    catch {
        Add-PsdError $Ctx 'PSD100' "the file $full can't be read: $($_.Exception.InnerException.Message)"
        return $null
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $text = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2) }
    else {
        $text = ConvertFrom-PsdUtf8 $bytes
        if ($null -eq $text) {
            Add-PsdError $Ctx 'PSD107' "the file isn't valid UTF-8. Save it as UTF-8." -File (New-PsdFileRec $full $null)
            return $null
        }
    }
    ConvertFrom-PsdText $text $full $Ctx
}

# Reads a file through -Loader: what it returns is the file, a map or a generated class made from one. Its
# directives ('!merge', '!include', '!name', '!schema') work as in a .psd1, paths relative to the file's folder.
function Read-PsdLoadedFile {
    # From is used inside the error script block below.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'From')]
    param([string] $Full, $Ctx, $From)
    $rec = New-PsdFileRec $Full $null
    $Ctx.Files[$rec.Key] = $rec
    $fail = {
        param([string] $Message)
        if ($From) { Add-PsdNodeError $Ctx 'PSD108' $Message $From } else { Add-PsdError $Ctx 'PSD108' $Message -File $rec }
    }
    try { $out = @(& $Ctx.Loader $Full | Where-Object { $null -ne $_ }) }
    catch {
        & $fail "-Loader couldn't read $($Full): $($_.Exception.Message)"
        return $rec
    }
    if ($out.Count -ne 1) {
        & $fail "-Loader has to give one map for $Full, but it gave $($out.Count) values."
        return $rec
    }
    $value = $out[0]
    if (-not (Test-PsdMapLike $value)) {
        & $fail "-Loader has to give a map for $Full, but it gave $(Get-PsdKindText $value)."
        return $rec
    }
    $rec.Root = ConvertFrom-PsdObject $value $rec $Ctx '' -AllowDirective
    $rec
}

function ConvertFrom-PsdText {
    param([string] $Text, [string] $Full, $Ctx)
    $rec = New-PsdFileRec $Full $Text
    $Ctx.Files[$rec.Key] = $rec
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseInput($Text, $Full, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) {
            if ($e.ErrorId -eq 'DuplicateKeyInHashLiteral') {
                Add-PsdExtentError $Ctx 'PSD102' "the key $($e.Extent.Text) is there twice in one map. Keys ignore case, so 'a' and 'A' count as the same key." $rec $e.Extent
            }
            else { Add-PsdExtentError $Ctx 'PSD101' "PowerShell can't read this: $($e.Message.TrimEnd('.'))." $rec $e.Extent }
        }
        return $rec
    }
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.DynamicParamBlock) {
        Add-PsdError $Ctx 'PSD105' 'a data file can only contain one @{ }, not a script.' -File $rec -Line 1
        return $rec
    }
    $stmts = @()
    if ($ast.EndBlock) { $stmts = @($ast.EndBlock.Statements) }
    if ($stmts.Count -eq 0) {
        Add-PsdError $Ctx 'PSD103' "the file is empty. A data file is one map: @{ ... }" -File $rec
        return $rec
    }
    $expr = Get-PsdStatementExpression $stmts[0]
    if ($expr -isnot [HashtableAst]) {
        Add-PsdExtentError $Ctx 'PSD103' 'a data file has to be one map: @{ ... }' $rec $stmts[0].Extent
        return $rec
    }
    if ($stmts.Count -gt 1) {
        Add-PsdExtentError $Ctx 'PSD104' 'there is something after the map. A data file is exactly one @{ ... }' $rec $stmts[1].Extent
        return $rec
    }
    $rec.Root = ConvertFrom-PsdHashAst $expr $rec $Ctx '' 0 $true $false
    $rec
}

function Get-PsdStatementExpression {
    param($Statement)
    if ($Statement -is [PipelineAst] -and $Statement.PipelineElements.Count -eq 1) {
        $el = $Statement.PipelineElements[0]
        if ($el -is [CommandExpressionAst] -and $el.Redirections.Count -eq 0) { return $el.Expression }
    }
    $null
}

function Get-PsdRejectText {
    param($Ast)
    if ($Ast -is [ConvertExpressionAst]) { return "casts like $($Ast.Type.Extent.Text) can't be used in a data file." }
    if ($Ast -is [ScriptBlockExpressionAst]) { return "script blocks { } can't be used in a data file, because they would be code." }
    if ($Ast -is [ParenExpressionAst] -or $Ast -is [SubExpressionAst]) { return "( ) and `$( ) can't be used in a data file." }
    if ($Ast -is [VariableExpressionAst]) { return "variables like $($Ast.Extent.Text) can't be used in a data file. Only `$true, `$false and `$null work. For environment variables, use '!<env:NAME>'." }
    if ($Ast -is [ExpandableStringExpressionAst]) { return "text in double quotes can't contain `$variables or `$( ). Use single quotes, or write ``$ for a dollar sign." }
    if ($Ast -is [PipelineAst] -or $Ast -is [CommandAst]) { return "commands can't be used in a data file. If this is text, put it in quotes." }
    if ($Ast -is [StringConstantExpressionAst]) { return "text needs quotes in a data file: '$($Ast.Value)'." }
    "this can't be used in a data file. Only text, numbers, `$true, `$false, `$null, @{ } and @( ) are allowed."
}

function Add-PsdReject {
    param($Ast, $File, $Ctx)
    Add-PsdExtentError $Ctx 'PSD105' (Get-PsdRejectText $Ast) $File $Ast.Extent
}

function New-PsdStringNode {
    param([string] $Value, $File, $Ast, [string] $Path, $Ctx)
    $node = New-PsdNode 'S' $Value $File $Ast $Path
    if ($Value.IndexOf('!<') -lt 0) { return $node }
    try { $tpl = ConvertFrom-PsdTemplate $Value }
    catch [System.FormatException] {
        Add-PsdNodeError $Ctx 'PSD300' $_.Exception.Message $node ([int]$_.Exception.Data['PsdPos']) ([int]$_.Exception.Data['PsdLen'])
        return $node
    }
    if (-not $tpl.HasRef) {
        $node.V = -join $tpl.Parts.ToArray()
        return $node
    }
    $node.K = 'T'
    $node.Parts = $tpl.Parts
    $node
}

function ConvertFrom-PsdAst {
    param($Ast, $File, $Ctx, [string] $Path, [int] $Depth, [bool] $InIf)
    if ($Depth -gt $Ctx.Limits.MaxDepth) { return (New-PsdTooDeepNode $File $Ast $Path $Ctx) }
    if ($Ast -is [HashtableAst]) { return (ConvertFrom-PsdHashAst $Ast $File $Ctx $Path $Depth $false $InIf) }
    if ($Ast -is [ArrayExpressionAst] -or $Ast -is [ArrayLiteralAst]) {
        $items = New-PsdList
        # @(@(1, 2)) is one flat list in PowerShell.
        $flat = $Ast -is [ArrayExpressionAst] -and $Ast.SubExpression.Statements.Count -eq 1
        foreach ($e in (Get-PsdArrayElements $Ast { param($st) Add-PsdReject $st $File $Ctx })) {
            if ($flat -and $e -is [ArrayExpressionAst]) {
                foreach ($x in (ConvertFrom-PsdAst $e $File $Ctx $Path ($Depth + 1)).V) { $items.Add($x) }
                continue
            }
            $items.Add((ConvertFrom-PsdAst $e $File $Ctx (Join-PsdPath $Path ([int]$items.Count)) ($Depth + 1)))
        }
        return (New-PsdNode 'L' $items $File $Ast $Path)
    }
    if ($Ast -is [StringConstantExpressionAst]) {
        if ($Ast.StringConstantType -ne [StringConstantType]::BareWord) { return (New-PsdStringNode $Ast.Value $File $Ast $Path $Ctx) }
    }
    elseif ($Ast -is [ExpandableStringExpressionAst]) {
        if ($Ast.NestedExpressions.Count -eq 0) { return (New-PsdStringNode $Ast.Value $File $Ast $Path $Ctx) }
    }
    elseif ($Ast -is [ConstantExpressionAst]) { return (New-PsdNode 'S' $Ast.Value $File $Ast $Path) }
    elseif ($Ast -is [VariableExpressionAst]) {
        switch ($Ast.VariablePath.UserPath.ToLowerInvariant()) {
            'true' { return (New-PsdNode 'S' $true $File $Ast $Path) }
            'false' { return (New-PsdNode 'S' $false $File $Ast $Path) }
            'null' { return (New-PsdNode 'S' $null $File $Ast $Path) }
        }
    }
    Add-PsdReject $Ast $File $Ctx
    New-PsdNode 'S' $null $File $Ast $Path
}

function ConvertFrom-PsdHashAst {
    param($Ast, $File, $Ctx, [string] $Path, [int] $Depth, [bool] $IsRoot, [bool] $InIf)
    $node = New-PsdMapNode $File $Ast $Path
    foreach ($pair in $Ast.KeyValuePairs) {
        $keyAst = $pair.Item1
        $kx = $keyAst.Extent
        $kinfo = @{ Line = $kx.StartLineNumber; Col = $kx.StartColumnNumber; Len = $kx.Text.Length; Text = $kx.Text; File = $File }
        if ($keyAst -isnot [StringConstantExpressionAst]) {
            Add-PsdKeyError $Ctx 'PSD106' "keys have to be text. Put this key in quotes: '$($kx.Text)'." $kinfo
            continue
        }
        $kc = Get-PsdKeyClass ([string]$keyAst.Value) $kinfo $Ctx
        if ($kc.Kind -eq 'Bad') { continue }
        $valueAst = Get-PsdStatementExpression $pair.Item2
        if ($null -eq $valueAst) { Add-PsdReject $pair.Item2 $File $Ctx; continue }
        $childPath = if ($kc.Kind -in 'Plain', 'Op') { Join-PsdPath $Path $kc.Name } else { $Path }
        # InIf: the body of an !if at the top of a file, where '!merge' and '!include' work
        $value = ConvertFrom-PsdAst $valueAst $File $Ctx $childPath ($Depth + 1) ($kc.Kind -eq 'If' -and ($IsRoot -or $InIf))
        Add-PsdMapEntry $node $kc $value $File $Ctx $IsRoot $InIf
    }
    $node
}

# Decides what a key is: a plain key, a merge operator, an !if, a directive.
function Get-PsdKeyClass {
    # Ctx is used inside the error script block below.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Ctx')]
    param([string] $Key, $KInfo, $Ctx)
    $kc = @{ Kind = 'Plain'; Name = $Key; Op = $null; Index = $null; Match = $null; Cond = $null; CondOffset = 0; Info = $KInfo }
    $err = {
        param($code, $msg, [string[]]$hint)
        Add-PsdKeyError $Ctx $code $msg $KInfo $Key $hint
        $kc.Kind = 'Bad'
    }
    $name = $Key
    if ($Key.StartsWith('!!')) { $name = $Key.Substring(1) }
    elseif ($Key.StartsWith('!')) {
        $m = [regex]::Match($Key, '^!if(\s+(.*))?$', 'IgnoreCase, Singleline')
        if ($m.Success) {
            $kc.Kind = 'If'
            $kc.Cond = $m.Groups[2].Value
            $kc.CondOffset = $Key.Length - $kc.Cond.Length
            return $kc
        }
        $lower = $Key.ToLowerInvariant()
        if ($script:PsdDirectives -contains $lower) { $kc.Kind = 'Dir'; $kc.Name = $lower; return $kc }
        $dym = Get-PsdDidYouMean $Key ($script:PsdDirectives + '!if')
        & $err 'PSD205' "'$Key' isn't a directive." @($dym, "Directives are !merge, !include, !name, !schema and !if. A real key that starts with ! is written '!$Key'.")
        return $kc
    }
    if ([regex]::IsMatch($name, '(?<!!)!<')) {
        & $err 'PSD305' "keys can't contain references. Keys stay fixed, so paths and schemas always work." @()
        return $kc
    }
    $m = $script:PsdRxOp.Match($name)
    if ($m.Success) {
        $kc.Kind = 'Op'
        $kc.Name = $m.Groups[1].Value
        $kc.Op = $m.Groups[2].Value
        # 'X[1] :=' works on one place of the list X. Without an operator, 'X[1]' stays a plain key.
        $im = $script:PsdRxIndexKey.Match($kc.Name)
        if ($im.Success) {
            if ($kc.Op -notin ':=', '-=', '+=') {
                & $err 'PSD209' "'$($kc.Op)' can't be used with an index." @('With an index: := replaces the item, -= removes it, += inserts before it.')
                return $kc
            }
            $kc.Name = $im.Groups[1].Value
            $text = $im.Groups[2].Value
            $index = 0
            # an index too big for an int is past the end of any list
            if (-not [int]::TryParse($text, [Globalization.NumberStyles]::AllowLeadingSign, $script:PsdInvariant, [ref]$index)) {
                $index = if ($text.StartsWith('-')) { [int]::MinValue } else { [int]::MaxValue }
            }
            $kc.Index = $index
            return $kc
        }
        # 'X[''b''] :=' works on the items of the list X that equal b.
        $vm = $script:PsdRxValueKey.Match($kc.Name)
        if ($vm.Success) {
            if ($kc.Op -notin ':=', '-=') {
                & $err 'PSD209' "'$($kc.Op)' can't be used with a value in [ ]." @('With a value: := replaces the items that equal it, -= removes them.')
                return $kc
            }
            $kc.Name = $vm.Groups[1].Value
            $kc.Match = if ($vm.Groups[2].Success) { $vm.Groups[2].Value.Replace("''", "'") } else { $vm.Groups[3].Value.Replace('""', '"') }
        }
        return $kc
    }
    $m = $script:PsdRxNearOp.Match($name)
    if ($m.Success) {
        $dym = Get-PsdDidYouMean $m.Groups[2].Value $script:PsdOperators
        & $err 'PSD209' "'$($m.Groups[2].Value)' at the end of this key looks like a merge operator, but isn't one." @($dym, 'Merge operators are +=, =+, |=, -= and :=, after a space.')
        return $kc
    }
    $kc.Name = $name
    $kc
}

function Add-PsdMapEntry {
    param($Node, $Kc, $Value, $File, $Ctx, [bool] $IsRoot, [bool] $InIf)
    $ki = $Kc.Info
    $Value.KeyLine = $ki.Line; $Value.KeyCol = $ki.Col; $Value.KeyLen = $ki.Len
    switch ($Kc.Kind) {
        'Plain' { $Node.V[$Kc.Name] = $Value }
        'Op' {
            $Node.Ops.Add(@{ Key = $Kc.Name; Op = $Kc.Op; Index = $Kc.Index; Match = $Kc.Match; Arg = $Value; File = $File; Line = $ki.Line; Col = $ki.Col; Len = $ki.Len; Text = $ki.Text; Path = (Join-PsdPath $Node.Path $Kc.Name) })
        }
        'If' {
            $ifNode = @{
                Id = New-PsdId; Cond = $null; Body = $Value; File = $File; Line = $ki.Line; Col = $ki.Col; Text = $ki.Text
                Offset = $Kc.CondOffset; Path = $Node.Path; Raw = $Kc.Cond; K = 'I'
            }
            if ($Value.K -ne 'M') {
                Add-PsdKeyError $Ctx 'PSD206' "an !if needs a map after it: '$($Kc.Cond)' = @{ ... }" $ki
                return
            }
            try { $ifNode.Cond = ConvertFrom-PsdCondition $Kc.Cond }
            catch [System.FormatException] {
                Add-PsdNodeError $Ctx 'PSD400' $_.Exception.Message $ifNode ([int]$_.Exception.Data['PsdPos']) ([int]$_.Exception.Data['PsdLen'])
                return
            }
            $Node.Ifs.Add($ifNode)
        }
        'Dir' {
            if ($InIf -and $Kc.Name -in '!merge', '!include') {
                Read-PsdDirective $Node $Kc.Name $Value $ki $Ctx
                return
            }
            if (-not $IsRoot) {
                Add-PsdKeyError $Ctx 'PSD206' "'$($Kc.Name)' only works at the top level of a file." $ki
                return
            }
            Read-PsdDirective $File $Kc.Name $Value $ki $Ctx
        }
    }
}

# The item nodes of a list node, or the node itself: what a value that can be one or many holds.
function Get-PsdNodeItems {
    param($Node)
    if ($Node.K -eq 'L') { $Node.V } else { $Node }
}

function Get-PsdPathStrings {
    param($Value, [string] $Directive, $Ctx, [string] $Shape)
    $out = New-PsdList
    foreach ($it in (Get-PsdNodeItems $Value)) {
        if ($it.K -eq 'S' -and $it.V -is [string] -and $it.V.Length -gt 0) { $out.Add(@{ Path = $it.V; Only = $null; Node = $it; Ref = $null }) }
        elseif ($it.K -eq 'T' -and $Directive -in '!merge', '!include') { $out.Add(@{ Path = $null; Only = $null; Node = $it; Ref = $it }) }
        elseif ($it.K -eq 'T') { Add-PsdNodeError $Ctx 'PSD206' "paths in '$Directive' can't contain references." $it }
        elseif ($Directive -eq '!merge' -and $it.K -eq 'M') {
            $spec = Read-PsdMergeMap $it $Ctx
            if ($spec) { $out.Add($spec) }
        }
        else { Add-PsdNodeError $Ctx 'PSD206' "'$Directive' takes $Shape." $it }
    }
    , $out
}

# '!merge' = @{ Path = '...'; Keys = 'A', 'B' } as a path entry, or $null when something is wrong with it.
function Read-PsdMergeMap {
    param($Item, $Ctx)
    $ok = $true
    foreach ($k in $Item.V.PSBase.Keys) {
        if ($k -notin 'Path', 'Keys') {
            Add-PsdNodeError $Ctx 'PSD206' "'$k' doesn't belong here. '!merge' takes @{ Path = '...'; Keys = 'A', 'B' }." $Item.V[$k]
            $ok = $false
        }
    }
    $p = $Item.V['Path']
    $isRef = $null -ne $p -and $p.K -eq 'T'
    if (-not $isRef -and ($null -eq $p -or $p.K -ne 'S' -or $p.V -isnot [string])) {
        Add-PsdNodeError $Ctx 'PSD206' "this needs a Path: @{ Path = './file.psd1'; Keys = 'A' }." $Item
        return $null
    }
    $keys = $null
    if ($Item.V['Keys']) {
        $keys = New-PsdList
        foreach ($x in (Get-PsdNodeItems $Item.V['Keys'])) {
            if ($x.K -eq 'S' -and $x.V -is [string]) { $keys.Add($x.V) }
            else { Add-PsdNodeError $Ctx 'PSD206' 'Keys has to be a key name or a list of key names.' $x; $ok = $false }
        }
    }
    if ($ok) {
        if ($isRef) { @{ Path = $null; Only = $keys; Node = $Item; Ref = $p } }
        else { @{ Path = $p.V; Only = $keys; Node = $Item; Ref = $null } }
    }
}

function Read-PsdDirective {
    param($File, [string] $Name, $Value, $KInfo, $Ctx)
    switch ($Name) {
        '!merge' {
            foreach ($x in (Get-PsdPathStrings $Value '!merge' $Ctx "a path, a list of paths, or @{ Path = '...'; Keys = 'A', 'B' }")) { $File.Merge.Add($x) }
        }
        '!include' {
            foreach ($x in (Get-PsdPathStrings $Value '!include' $Ctx 'a path or a list of paths')) { $File.Include.Add($x) }
        }
        '!types' {
            if (-not $Ctx.SchemaMode) {
                Add-PsdKeyError $Ctx 'PSD205' "'!types' only works in a schema file." $KInfo
                return
            }
            foreach ($x in (Get-PsdPathStrings $Value '!types' $Ctx 'a path or a list of paths to .psm1 files')) { $File.Types.Add($x) }
        }
        '!schema' {
            if ($Value.K -ne 'S' -or $Value.V -isnot [string]) { Add-PsdNodeError $Ctx 'PSD206' "'!schema' takes the path of a schema file." $Value; return }
            $File.Schema = @{ Path = $Value.V; Node = $Value }
        }
        '!name' {
            if ($Value.K -ne 'S' -or $Value.V -isnot [string] -or -not $script:PsdRxFileName.IsMatch($Value.V)) {
                Add-PsdNodeError $Ctx 'PSD206' "'!name' takes a name without spaces or signs like :, @ or !." $Value
                return
            }
            if ($Value.V -ieq 'this') {
                Add-PsdNodeError $Ctx 'PSD204' "'this' can't be a file's name, because this:: always means the file it's written in." $Value
                return
            }
            $File.Ns = $Value.V
            if ($File.Synthetic) {
                $File.Name = $Value.V
                $File.Label = $Value.V
                $File.Named = $true
                $File.Path = [IO.Path]::Combine($File.Dir, "($($Value.V))")
            }
        }
    }
}

# --- Plain objects to nodes -------------------------------------------------------

function New-PsdSyntheticFile {
    param([string] $Name, [string] $Dir)
    if (-not $Dir) { $Dir = (Get-Location -PSProvider FileSystem).ProviderPath }
    $rec = New-PsdFileRec ([IO.Path]::Combine($Dir, "($Name)")) $null
    $rec.Name = $Name
    $rec.Ext = ''
    $rec.Ns = $Name
    $rec.Synthetic = $true
    $rec.Label = "the $Name"
    $rec
}

# The map a generated class was made from, or $null.
function Get-PsdKeptMap {
    param($Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [System.Collections.IEnumerable]) { return $null }
    $prop = $Value.GetType().GetProperty('__PsdMap')
    if ($null -eq $prop) { return $null }
    $prop.GetValue($Value, $null)
}

# AllowName: '!name' at the top works, for maps given to Merge-Psd. AllowDirective: every directive at the top
# works, for files read through -Loader. InIf: the body of an !if at the top of such a file.
function ConvertFrom-PsdObject {
    param($Value, $File, $Ctx, [string] $Path, [int] $Depth = 0, [switch] $AllowName, [switch] $AllowDirective, [switch] $InIf)
    if ($Depth -gt $Ctx.Limits.MaxDepth) { return (New-PsdTooDeepNode $File $null $Path $Ctx) }
    if ($null -eq $Value) { return (New-PsdNode 'S' $null $File $null $Path) }
    if ($Value -is [System.Collections.IDictionary]) {
        $node = New-PsdMapNode $File $null $Path
        foreach ($k in @($Value.PSBase.Keys)) {
            $kinfo = @{ Line = 0; Col = 0; Len = 0; Text = [string]$k; File = $File }
            $kc = Get-PsdKeyClass ([string]$k) $kinfo $Ctx
            if ($kc.Kind -eq 'Bad') { continue }
            $childPath = if ($kc.Kind -in 'Plain', 'Op') { Join-PsdPath $Path $kc.Name } else { $Path }
            $childInIf = $kc.Kind -eq 'If' -and ($InIf -or ($AllowDirective -and $Depth -eq 0))
            $child = ConvertFrom-PsdObject $Value[$k] $File $Ctx $childPath ($Depth + 1) -InIf:$childInIf
            if ($kc.Kind -eq 'Dir') {
                if ($InIf -and $kc.Name -in '!merge', '!include') { Read-PsdDirective $node $kc.Name $child $kinfo $Ctx }
                elseif ($Depth -eq 0 -and ($AllowDirective -or ($AllowName -and $kc.Name -eq '!name'))) { Read-PsdDirective $File $kc.Name $child $kinfo $Ctx }
                else { Add-PsdError $Ctx 'PSD206' "'$($kc.Name)' only works in files." -File $File -Key ([string]$k) }
                continue
            }
            Add-PsdMapEntry $node $kc $child $File $Ctx $false $false
        }
        return $node
    }
    if ($Value -is [string]) { return (New-PsdStringNode $Value $File $null $Path $Ctx) }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = New-PsdList
        foreach ($x in $Value) { $items.Add((ConvertFrom-PsdObject $x $File $Ctx (Join-PsdPath $Path ([int]$items.Count)) ($Depth + 1))) }
        return (New-PsdNode 'L' $items $File $null $Path)
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $map[$p.Name] = $p.Value }
        return (ConvertFrom-PsdObject $map $File $Ctx $Path $Depth -AllowName:$AllowName -AllowDirective:$AllowDirective -InIf:$InIf)
    }
    $kept = Get-PsdKeptMap $Value
    if ($null -ne $kept) { return (ConvertFrom-PsdObject $kept $File $Ctx $Path $Depth -AllowName:$AllowName -AllowDirective:$AllowDirective -InIf:$InIf) }
    New-PsdNode 'S' $Value $File $null $Path
}
