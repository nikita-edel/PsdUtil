using namespace System.Management.Automation.Language

# Edits files in place. Only the changed text is touched, so comments stay.

function Read-PsdRawFile {
    param([string] $Path, $Ctx)
    if (-not [IO.File]::Exists($Path)) { Add-PsdError $Ctx 'PSD100' "the file $Path doesn't exist."; return $null }
    try { $bytes = [IO.File]::ReadAllBytes($Path) }
    catch {
        Add-PsdError $Ctx 'PSD100' "the file $Path can't be read: $($_.Exception.InnerException.Message)"
        return $null
    }
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    # Strict: bytes that aren't UTF-8 would be replaced when read, and the damage written back.
    try { $text = (New-Object System.Text.UTF8Encoding $false, $true).GetString($bytes) }
    catch {
        Add-PsdError $Ctx 'PSD606' "the file can't be edited, because it isn't valid UTF-8. Save it as UTF-8." -File (New-PsdFileRec $Path $null)
        return $null
    }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseInput($text, $Path, [ref]$tokens, [ref]$errors)
    $rec = New-PsdFileRec $Path $text
    if ($errors.Count -gt 0) {
        Add-PsdExtentError $Ctx 'PSD606' "the file can't be edited, because PowerShell can't read it: $($errors[0].Message.TrimEnd('.'))." $rec $errors[0].Extent
        return $null
    }
    $root = $null
    if ($ast.EndBlock -and $ast.EndBlock.Statements.Count -eq 1) { $root = Get-PsdStatementExpression $ast.EndBlock.Statements[0] }
    if ($root -isnot [HashtableAst]) {
        Add-PsdError $Ctx 'PSD606' "the file can't be edited, because it isn't one map: @{ ... }" -File $rec
        return $null
    }
    @{ Text = $text; Bom = $bom; NL = $nl; Ast = $ast; Root = $root; Tokens = $tokens; Rec = $rec }
}

function Get-PsdLineIndent {
    param([string] $Text, [int] $Offset)
    $start = $Text.LastIndexOf("`n", [Math]::Max(0, $Offset - 1))
    if ($Offset -eq 0) { $start = -1 }
    $start++
    $i = $start
    while ($i -lt $Text.Length -and ($Text[$i] -eq ' ' -or $Text[$i] -eq "`t")) { $i++ }
    $Text.Substring($start, $i - $start)
}

function Add-PsdIndent {
    param([string] $Text, [string] $Indent, [string] $NL)
    $lines = $Text -split '\r?\n'
    for ($i = 1; $i -lt $lines.Count; $i++) { $lines[$i] = $Indent + $lines[$i] }
    $lines -join $NL
}

# The items of an array expression. OnReject gets each statement that isn't a plain value.
function Get-PsdArrayElements {
    param($Ast, [scriptblock] $OnReject = {})
    $out = New-PsdList
    if ($Ast -is [ArrayLiteralAst]) { foreach ($x in $Ast.Elements) { $out.Add($x) }; return , $out }
    foreach ($st in $Ast.SubExpression.Statements) {
        $e = Get-PsdStatementExpression $st
        if ($null -eq $e) { & $OnReject $st }
        elseif ($e -is [ArrayLiteralAst]) { foreach ($x in $e.Elements) { $out.Add($x) } }
        else { $out.Add($e) }
    }
    , $out
}

# The edit that replaces a value. IndentAt is where the line that sets the indentation is.
function New-PsdValueEdit {
    param($Raw, $Target, [int] $IndentAt, $Value, $Format, $Ctx)
    $vt = ConvertTo-PsdTextInternal $Value $Format 64 $Ctx
    @{ Start = $Target.Extent.StartOffset; End = $Target.Extent.EndOffset; Text = (Add-PsdIndent $vt (Get-PsdLineIndent $Raw.Text $IndentAt) $Raw.NL) }
}

# The edit that adds key number At of the path to Map. The rest of the path becomes nested maps. $null on errors.
function New-PsdNewKeyEdit {
    param($Raw, $Map, $Segs, [int] $At, $Value, $Format, $Ctx)
    $text = $Raw.Text
    $nl = $Raw.NL
    $v = $Value
    for ($j = $Segs.Count - 1; $j -gt $At; $j--) {
        if ($Segs[$j].IsIndex) {
            Add-PsdError $Ctx 'PSD607' "$(Format-PsdSegs $Segs $j) doesn't exist, so [$($Segs[$j].Index)] can't be set." -File $Raw.Rec
            return $null
        }
        $m = [ordered]@{}; $m[$Segs[$j].Key] = $v; $v = $m
    }
    $keyText = Format-PsdKeyOut $Segs[$At].Key @{ Ctx = $Ctx; Path = (Format-PsdSegs $Segs $At) }
    if ($null -eq $keyText) { return $null }
    $hs = $Map.Extent.StartOffset
    $he = $Map.Extent.EndOffset
    if ($Map.KeyValuePairs.Count -gt 0) { $indent = Get-PsdLineIndent $text $Map.KeyValuePairs[0].Item1.Extent.StartOffset }
    else { $indent = (Get-PsdLineIndent $text $hs) + (' ' * $Format.Indent) }
    $entry = "$keyText = " + (Add-PsdIndent (ConvertTo-PsdTextInternal $v $Format 64 $Ctx) $indent $nl)
    if ($Map.Extent.StartLineNumber -ne $Map.Extent.EndLineNumber) {
        $close = $he - 1
        $lineStart = $text.LastIndexOf("`n", $close - 1) + 1
        if ($text.Substring($lineStart, $close - $lineStart).Trim().Length -eq 0) { return @{ Start = $lineStart; End = $lineStart; Text = "$indent$entry$nl" } }
        return @{ Start = $close; End = $close; Text = "$nl$indent$entry$nl$(Get-PsdLineIndent $text $hs)" }
    }
    if ($Map.KeyValuePairs.Count -eq 0) { return @{ Start = $hs; End = $he; Text = "@{ $entry }" } }
    $end = $Map.KeyValuePairs[$Map.KeyValuePairs.Count - 1].Item2.Extent.EndOffset
    @{ Start = $end; End = $end; Text = "; $entry" }
}

function Update-PsdFileValue {
    param([string] $Path, $Segs, $Value, $Format, $Ctx)
    $raw = Read-PsdRawFile $Path $Ctx
    if ($null -eq $raw) { return $false }
    $text = $raw.Text
    $Format.LineEnding = if ($raw.NL -eq "`r`n") { 'CRLF' } else { 'LF' }
    $fail = { param($message) Add-PsdError $Ctx 'PSD607' $message -File $raw.Rec }
    $cur = $raw.Root
    $edit = $null
    for ($i = 0; $i -lt $Segs.Count; $i++) {
        $seg = $Segs[$i]
        $last = ($i -eq $Segs.Count - 1)
        $under = Format-PsdSegs $Segs $i
        $shownUnder = if ($under) { $under } else { 'the file' }
        if ($cur -is [HashtableAst]) {
            if ($seg.IsIndex) { & $fail "$shownUnder is a map, so [$($seg.Index)] can't be used on it."; return $false }
            $pair = $null
            foreach ($p in $cur.KeyValuePairs) {
                if ($p.Item1 -is [StringConstantExpressionAst] -and $p.Item1.Value -ieq $seg.Key) { $pair = $p; break }
            }
            if (-not $pair) { $edit = New-PsdNewKeyEdit $raw $cur $Segs $i $Value $Format $Ctx; break }
            $expr = Get-PsdStatementExpression $pair.Item2
            if ($null -eq $expr) { & $fail "$(Format-PsdSegs $Segs ($i + 1)) isn't a plain value, so it can't be changed."; return $false }
            if ($last) { $edit = New-PsdValueEdit $raw $expr $pair.Item1.Extent.StartOffset $Value $Format $Ctx; break }
            $cur = $expr
            continue
        }
        if ($cur -is [ArrayExpressionAst] -or $cur -is [ArrayLiteralAst]) {
            if (-not $seg.IsIndex) { & $fail "$shownUnder is a list, so .$($seg.Key) can't be used on it."; return $false }
            $els = Get-PsdArrayElements $cur
            $idx = $seg.Index
            if ($idx -lt 0) { $idx += $els.Count }
            if ($idx -lt 0 -or $idx -ge $els.Count) { & $fail "$shownUnder has $($els.Count) items, so [$($seg.Index)] doesn't exist."; return $false }
            if ($last) { $edit = New-PsdValueEdit $raw $els[$idx] $els[$idx].Extent.StartOffset $Value $Format $Ctx; break }
            $cur = $els[$idx]
            continue
        }
        & $fail "$shownUnder is a single value, so it has nothing inside it to change."
        return $false
    }
    if ($Ctx.Errors.Count -gt 0 -or $null -eq $edit) { return $false }
    $new = $text.Substring(0, $edit.Start) + $edit.Text + $text.Substring($edit.End)
    Write-PsdTextFile $Path $new $raw.Bom $Ctx
}

# Re-indents by nesting depth and trims trailing spaces. Comments and strings stay.
function Format-PsdFileText {
    param([string] $Path, $Format, [bool] $BomGiven, $Ctx)
    $raw = Read-PsdRawFile $Path $Ctx
    if ($null -eq $raw) { return $false }
    $text = $raw.Text
    $nl = $raw.NL
    switch ($Format.LineEnding) { 'LF' { $nl = "`n" } 'CRLF' { $nl = "`r`n" } }
    $opens = @('AtCurly', 'LCurly', 'AtParen', 'LParen', 'DollarParen', 'LBracket')
    $closes = @('RCurly', 'RParen', 'RBracket')
    $tokens = New-PsdList
    foreach ($t in $raw.Tokens) { if ($t.Kind -ne 'NewLine' -and $t.Kind -ne 'EndOfInput' -and $t.Kind -ne 'LineContinuation') { $tokens.Add($t) } }

    $lines = $text -split '\r?\n'
    $starts = New-Object 'int[]' $lines.Count
    $off = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $starts[$i] = $off
        $off += $lines[$i].Length
        if ($off -lt $text.Length -and $text[$off] -eq "`r") { $off++ }
        $off++
    }

    $out = New-PsdList
    $depth = 0
    $ti = 0
    $info = New-PsdList
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $s = $starts[$i]
        $inside = $false
        while ($ti -lt $tokens.Count -and $tokens[$ti].Extent.StartOffset -lt $s) {
            $t = $tokens[$ti]
            if ($opens -contains [string]$t.Kind) { $depth++ }
            elseif ($closes -contains [string]$t.Kind) { $depth = [Math]::Max(0, $depth - 1) }
            if ($t.Extent.EndOffset -gt $s) { $inside = $true }
            $ti++
        }
        # A token that continues past this line keeps its own line breaks.
        if ($inside) { $out.Add($lines[$i]); $info.Add($null); continue }
        $trim = $lines[$i].Trim()
        if ($trim.Length -eq 0) { $out.Add(''); $info.Add($null); continue }
        $d = $depth
        $first = $null; $second = $null
        if ($ti -lt $tokens.Count -and $tokens[$ti].Extent.StartLineNumber -eq ($i + 1)) {
            $first = $tokens[$ti]
            if ($ti + 1 -lt $tokens.Count -and $tokens[$ti + 1].Extent.StartLineNumber -eq ($i + 1)) { $second = $tokens[$ti + 1] }
        }
        if ($first -and $closes -contains [string]$first.Kind) { $d = [Math]::Max(0, $d - 1) }
        $out.Add((' ' * ($Format.Indent * $d)) + $trim)
        $isKey = $first -and $second -and [string]$second.Kind -eq 'Equals' -and $d -gt 0
        if ($isKey) { $info.Add(@{ Depth = $d; Key = $first.Extent.Text }) } else { $info.Add($null) }
    }
    if ($Format.AlignEquals) {
        $i = 0
        while ($i -lt $out.Count) {
            if ($null -eq $info[$i]) { $i++; continue }
            $j = $i
            $width = 0
            while ($j -lt $out.Count -and $info[$j] -and $info[$j].Depth -eq $info[$i].Depth) { $width = [Math]::Max($width, $info[$j].Key.Length); $j++ }
            for ($k = $i; $k -lt $j; $k++) {
                $line = $out[$k]
                $pad = ' ' * ($Format.Indent * $info[$k].Depth)
                $rest = $line.Substring($pad.Length + $info[$k].Key.Length).TrimStart()
                if ($rest.StartsWith('=')) { $out[$k] = $pad + $info[$k].Key.PadRight($width) + ' ' + $rest }
            }
            $i = $j
        }
    }
    $new = $out -join $nl
    $bom = $raw.Bom
    if ($BomGiven) { $bom = $Format.Bom }
    Write-PsdTextFile $Path $new $bom $Ctx
}
