using namespace System.Management.Automation.Language

# Turns files (or plain objects) into a tree of values, without running any code.

$script:PsdRxOp = New-Object regex '^(.*\S) (\+=|=\+|\|=|-=|:=)$'
$script:PsdRxNearOp = New-Object regex '^(.*\S) ([-+=|:]{1,3})$'
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
        Parts = $null; Ops = $null; Ifs = $null; Base = $null; Op = $null; Arg = $null; Offset = 0
        KeyLine = 0; KeyCol = 0; KeyLen = 0
    }
    if ($Ast) {
        $n.Line = $Ast.Extent.StartLineNumber
        $n.Col = $Ast.Extent.StartColumnNumber
        $n.Text = $Ast.Extent.Text
    }
    $n
}

function New-PsdMapNode {
    param($File, $Ast, [string] $Path)
    $n = New-PsdNode 'M' ([ordered]@{}) $File $Ast $Path
    $n.Ops = New-PsdList
    $n.Ifs = New-PsdList
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
    elseif ($text.Length -gt 0 -and "'`"".IndexOf($text[0]) -ge 0 -or ($text.Length -gt 0 -and [int]$text[0] -ge 0x2018 -and [int]$text[0] -le 0x201E)) {
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

# --- Reading files --------------------------------------------------------------

function Read-PsdFile {
    param([string] $Path, $Ctx, $From = $null, [string] $Code = 'PSD100')
    $full = [IO.Path]::GetFullPath($Path)
    $key = Get-PsdPathKey $full
    if ($Ctx.Files.ContainsKey($key)) { return $Ctx.Files[$key] }
    if (-not [IO.File]::Exists($full)) {
        $msg = "the file $full doesn't exist."
        if ($From) { Add-PsdNodeError $Ctx $Code $msg $From } else { Add-PsdError $Ctx $Code $msg }
        return $null
    }
    if ($Ctx.Files.Count -ge $Ctx.Limits.MaxFiles) {
        Add-PsdLimitError $Ctx 'MaxFiles' "while loading $full"
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
    $text = $null
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $text = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2) }
    else {
        $enc = New-Object System.Text.UTF8Encoding $false, $true
        try { $text = $enc.GetString($bytes) }
        catch {
            $rec = New-PsdFileRec $full $null
            Add-PsdError $Ctx 'PSD107' "the file isn't valid UTF-8. Save it as UTF-8." -File $rec
            return $null
        }
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    }
    ConvertFrom-PsdText $text $full $Ctx
}

function ConvertFrom-PsdText {
    param([string] $Text, [string] $Full, $Ctx)
    $rec = New-PsdFileRec $Full $Text
    $Ctx.Files[$rec.Key] = $rec
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseInput($Text, $Full, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) {
            $x = $e.Extent
            if ($e.ErrorId -eq 'DuplicateKeyInHashLiteral') {
                Add-PsdError $Ctx 'PSD102' "the key $($x.Text) is there twice in one map. Keys ignore case, so 'a' and 'A' count as the same key." `
                    -File $rec -Line $x.StartLineNumber -Column $x.StartColumnNumber -Length $x.Text.Length
            }
            else {
                $msg = $e.Message.TrimEnd('.')
                Add-PsdError $Ctx 'PSD101' "PowerShell can't read this: $msg." -File $rec -Line $x.StartLineNumber -Column $x.StartColumnNumber -Length ([Math]::Max(1, $x.Text.Length))
            }
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
        $x = $stmts[0].Extent
        Add-PsdError $Ctx 'PSD103' 'a data file has to be one map: @{ ... }' -File $rec -Line $x.StartLineNumber -Column $x.StartColumnNumber -Length (($x.Text -split '\r?\n')[0].Length)
        return $rec
    }
    if ($stmts.Count -gt 1) {
        $x = $stmts[1].Extent
        Add-PsdError $Ctx 'PSD104' 'there is something after the map. A data file is exactly one @{ ... }' -File $rec -Line $x.StartLineNumber -Column $x.StartColumnNumber -Length (($x.Text -split '\r?\n')[0].Length)
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
    $x = $Ast.Extent
    Add-PsdError $Ctx 'PSD105' (Get-PsdRejectText $Ast) -File $File -Line $x.StartLineNumber -Column $x.StartColumnNumber -Length (($x.Text -split '\r?\n')[0].Length)
}

function New-PsdStringNode {
    param([string] $Value, $File, $Ast, [string] $Path, $Ctx)
    $node = New-PsdNode 'S' $Value $File $Ast $Path
    if ($Value.IndexOf('!<') -lt 0) { return $node }
    try { $tpl = ConvertFrom-PsdTemplate $Value }
    catch [System.FormatException] {
        $pos = [int]$_.Exception.Data['PsdPos']
        $len = [int]$_.Exception.Data['PsdLen']
        Add-PsdNodeError $Ctx 'PSD300' $_.Exception.Message $node $pos $len
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
    if ($Depth -gt $Ctx.Limits.MaxDepth) {
        Add-PsdLimitError $Ctx 'MaxDepth' "by nesting at $Path" $File $Ast.Extent.StartLineNumber $Ast.Extent.StartColumnNumber
        return (New-PsdNode 'S' $null $File $Ast $Path)
    }
    if ($Ast -is [HashtableAst]) { return (ConvertFrom-PsdHashAst $Ast $File $Ctx $Path $Depth $false $InIf) }
    if ($Ast -is [ArrayExpressionAst] -or $Ast -is [ArrayLiteralAst]) {
        $items = New-PsdList
        $exprs = New-PsdList
        if ($Ast -is [ArrayLiteralAst]) { foreach ($x in $Ast.Elements) { $exprs.Add($x) } }
        else {
            foreach ($st in $Ast.SubExpression.Statements) {
                $e = Get-PsdStatementExpression $st
                if ($null -eq $e) { Add-PsdReject $st $File $Ctx; continue }
                if ($e -is [ArrayLiteralAst]) { foreach ($x in $e.Elements) { $exprs.Add($x) } }
                else { $exprs.Add($e) }
            }
        }
        foreach ($e in $exprs) {
            if ($Ast -is [ArrayExpressionAst] -and $e -is [ArrayExpressionAst] -and $Ast.SubExpression.Statements.Count -eq 1) {
                # @(@(1, 2)) is one flat list in PowerShell.
                $inner = ConvertFrom-PsdAst $e $File $Ctx $Path ($Depth + 1) $InIf
                foreach ($x in $inner.V) { $items.Add($x) }
                continue
            }
            $items.Add((ConvertFrom-PsdAst $e $File $Ctx (Join-PsdPath $Path ([int]$items.Count)) ($Depth + 1) $InIf))
        }
        return (New-PsdNode 'L' $items $File $Ast $Path)
    }
    if ($Ast -is [StringConstantExpressionAst]) {
        if ($Ast.StringConstantType -eq [StringConstantType]::BareWord) { Add-PsdReject $Ast $File $Ctx; return (New-PsdNode 'S' $null $File $Ast $Path) }
        return (New-PsdStringNode $Ast.Value $File $Ast $Path $Ctx)
    }
    if ($Ast -is [ExpandableStringExpressionAst]) {
        if ($Ast.NestedExpressions.Count -eq 0) { return (New-PsdStringNode $Ast.Value $File $Ast $Path $Ctx) }
        Add-PsdReject $Ast $File $Ctx
        return (New-PsdNode 'S' $null $File $Ast $Path)
    }
    if ($Ast -is [ConstantExpressionAst]) { return (New-PsdNode 'S' $Ast.Value $File $Ast $Path) }
    if ($Ast -is [VariableExpressionAst]) {
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
            Add-PsdError $Ctx 'PSD106' "keys have to be text. Put this key in quotes: '$($kx.Text)'." -File $File -Line $kinfo.Line -Column $kinfo.Col -Length $kinfo.Len
            continue
        }
        $kc = Get-PsdKeyClass ([string]$keyAst.Value) $kinfo $Ctx
        if ($kc.Kind -eq 'Bad') { continue }
        $valueAst = Get-PsdStatementExpression $pair.Item2
        if ($null -eq $valueAst) { Add-PsdReject $pair.Item2 $File $Ctx; continue }
        $childPath = $Path
        if ($kc.Kind -eq 'Plain' -or $kc.Kind -eq 'Op') { $childPath = Join-PsdPath $Path $kc.Name }
        $value = ConvertFrom-PsdAst $valueAst $File $Ctx $childPath ($Depth + 1) ($InIf -or $kc.Kind -eq 'If')
        Add-PsdMapEntry $node $kc $value $File $Ctx $IsRoot $InIf
    }
    $node
}

# Decides what a key is: a plain key, a merge operator, an !if, a directive.
function Get-PsdKeyClass {
    # Ctx is used inside the error script block below.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Ctx')]
    param([string] $Key, $KInfo, $Ctx)
    $kc = @{ Kind = 'Plain'; Name = $Key; Op = $null; Cond = $null; CondOffset = 0; Info = $KInfo }
    $err = {
        param($code, $msg, [string[]]$hint)
        Add-PsdError $Ctx $code $msg -File $KInfo.File -Line $KInfo.Line -Column $KInfo.Col -Length $KInfo.Len -Key $Key -Hint $hint
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
            $Node.Ops.Add(@{ Key = $Kc.Name; Op = $Kc.Op; Arg = $Value; File = $File; Line = $ki.Line; Col = $ki.Col; Len = $ki.Len; Text = $ki.Text; Path = (Join-PsdPath $Node.Path $Kc.Name) })
        }
        'If' {
            $ifNode = @{
                Id = New-PsdId; Cond = $null; Body = $Value; File = $File; Line = $ki.Line; Col = $ki.Col; Text = $ki.Text
                Offset = $Kc.CondOffset; Path = $Node.Path; Raw = $Kc.Cond; K = 'I'
            }
            if ($InIf) {
                Add-PsdError $Ctx 'PSD206' "an !if can't contain another !if. Join the conditions with -and instead." -File $File -Line $ki.Line -Column $ki.Col -Length $ki.Len
                return
            }
            if ($Value.K -ne 'M') {
                Add-PsdError $Ctx 'PSD206' "an !if needs a map after it: '$($Kc.Cond)' = @{ ... }" -File $File -Line $ki.Line -Column $ki.Col -Length $ki.Len
                return
            }
            try { $ifNode.Cond = ConvertFrom-PsdCondition $Kc.Cond }
            catch [System.FormatException] {
                $pos = [int]$_.Exception.Data['PsdPos']
                $len = [int]$_.Exception.Data['PsdLen']
                Add-PsdNodeError $Ctx 'PSD400' $_.Exception.Message $ifNode $pos $len
                return
            }
            $Node.Ifs.Add($ifNode)
        }
        'Dir' {
            if (-not $IsRoot) {
                Add-PsdError $Ctx 'PSD206' "'$($Kc.Name)' only works at the top level of a file." -File $File -Line $ki.Line -Column $ki.Col -Length $ki.Len
                return
            }
            Read-PsdDirective $File $Kc.Name $Value $ki $Ctx
        }
    }
}

function Get-PsdPathStrings {
    param($Value, [string] $Directive, $Ctx, [string] $Shape)
    $out = New-PsdList
    $items = Get-PsdItems $Value
    if ($Value.K -eq 'L') { $items = Get-PsdItems $Value.V }
    foreach ($it in $items) {
        if ($it.K -eq 'S' -and $it.V -is [string] -and $it.V.Length -gt 0) { $out.Add(@{ Path = $it.V; Only = $null; Node = $it }); continue }
        if ($it.K -eq 'T') { Add-PsdNodeError $Ctx 'PSD206' "paths in '$Directive' can't contain references." $it; continue }
        if ($Directive -eq '!merge' -and $it.K -eq 'M') {
            $ok = $true
            foreach ($k in $it.V.PSBase.Keys) {
                if ($k -ne 'Path' -and $k -ne 'Keys') {
                    Add-PsdNodeError $Ctx 'PSD206' "'$k' doesn't belong here. '!merge' takes @{ Path = '...'; Keys = 'A', 'B' }." $it.V[$k]
                    $ok = $false
                }
            }
            $p = $it.V['Path']
            if ($null -eq $p -or $p.K -ne 'S' -or $p.V -isnot [string]) {
                Add-PsdNodeError $Ctx 'PSD206' "this needs a Path: @{ Path = './file.psd1'; Keys = 'A' }." $it
                continue
            }
            $keys = New-PsdList
            $kn = $it.V['Keys']
            if ($kn) {
                $kitems = Get-PsdItems $kn
                if ($kn.K -eq 'L') { $kitems = Get-PsdItems $kn.V }
                foreach ($x in $kitems) {
                    if ($x.K -eq 'S' -and $x.V -is [string]) { $keys.Add($x.V) }
                    else { Add-PsdNodeError $Ctx 'PSD206' 'Keys has to be a key name or a list of key names.' $x; $ok = $false }
                }
            }
            if ($ok) {
                $kl = $null
                if ($kn) { $kl = $keys }
                $out.Add(@{ Path = $p.V; Only = $kl; Node = $it })
            }
            continue
        }
        Add-PsdNodeError $Ctx 'PSD206' "'$Directive' takes $Shape." $it
    }
    , $out
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
                Add-PsdError $Ctx 'PSD205' "'!types' only works in a schema file." -File $File -Line $KInfo.Line -Column $KInfo.Col -Length $KInfo.Len
                return
            }
            foreach ($x in (Get-PsdPathStrings $Value '!types' $Ctx 'a path or a list of paths to .psm1 files')) { $File.Types.Add($x) }
        }
        '!schema' {
            if ($Value.K -ne 'S' -or $Value.V -isnot [string]) { Add-PsdNodeError $Ctx 'PSD206' "'!schema' takes the path of a schema file." $Value; return }
            $File.Schema = @{ Path = $Value.V; Node = $Value }
        }
        '!name' {
            if ($Value.K -ne 'S' -or $Value.V -isnot [string] -or $Value.V -notmatch '^[^\s"<>|?()\[\],:@!]+$') {
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

function ConvertFrom-PsdObject {
    param($Value, $File, $Ctx, [string] $Path, [int] $Depth = 0, [switch] $AllowName)
    if ($Depth -gt $Ctx.Limits.MaxDepth) {
        Add-PsdLimitError $Ctx 'MaxDepth' "by nesting at $Path" $File
        return (New-PsdNode 'S' $null $File $null $Path)
    }
    if ($null -eq $Value) { return (New-PsdNode 'S' $null $File $null $Path) }
    if ($Value -is [System.Collections.IDictionary]) {
        $node = New-PsdMapNode $File $null $Path
        foreach ($k in @($Value.PSBase.Keys)) {
            $kinfo = @{ Line = 0; Col = 0; Len = 0; Text = [string]$k; File = $File }
            $kc = Get-PsdKeyClass ([string]$k) $kinfo $Ctx
            if ($kc.Kind -eq 'Bad') { continue }
            $childPath = $Path
            if ($kc.Kind -eq 'Plain' -or $kc.Kind -eq 'Op') { $childPath = Join-PsdPath $Path $kc.Name }
            $child = ConvertFrom-PsdObject $Value[$k] $File $Ctx $childPath ($Depth + 1)
            if ($kc.Kind -eq 'Dir') {
                if ($AllowName -and $Depth -eq 0 -and $kc.Name -eq '!name') {
                    Read-PsdDirective $File '!name' $child $kinfo $Ctx
                    continue
                }
                Add-PsdError $Ctx 'PSD206' "'$($kc.Name)' only works in files." -File $File -Key ([string]$k)
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
        return (ConvertFrom-PsdObject $map $File $Ctx $Path $Depth -AllowName:$AllowName)
    }
    $kept = Get-PsdKeptMap $Value
    if ($null -ne $kept) { return (ConvertFrom-PsdObject $kept $File $Ctx $Path $Depth -AllowName:$AllowName) }
    New-PsdNode 'S' $Value $File $null $Path
}
