# Tokenizer and parser for references (!<...>), paths and conditions.
# Hand-written so every error can point to an exact column.

$script:PsdRxName = New-Object regex '\G[A-Za-z_][A-Za-z0-9_\-]*'
$script:PsdRxInt = New-Object regex '\G-?[0-9]+'
$script:PsdRxNumber = New-Object regex '\G-?[0-9]+(\.[0-9]+)?'
$script:PsdRxNs = New-Object regex '\G([^\s"<>|?()\[\],:@!]+)::'
$script:PsdRxEnv = New-Object regex '\G[eE][nN][vV]:'
$script:PsdRxEnvName = New-Object regex '\G[A-Za-z_][A-Za-z0-9_]*'
$script:PsdRxCmpOp = New-Object regex '\G-(eq|ne|gt|ge|lt|le|in|like|match)(?![A-Za-z0-9_])', 'IgnoreCase'
$script:PsdRxWord = New-Object regex '\G(true|false|null)(?![A-Za-z0-9_\-])', 'IgnoreCase'
$script:PsdRxPlainKey = New-Object regex '^[A-Za-z_][A-Za-z0-9_\-]*$'
$script:PsdRxIdent = New-Object regex '^[A-Za-z_][A-Za-z0-9_]*$'
$script:PsdRxFileName = New-Object regex '^[^\s"<>|?()\[\],:@!]+$'

function New-PsdParser {
    param([string] $Text, [int] $Pos = 0)
    @{ T = $Text; P = $Pos }
}

function Stop-PsdParse {
    param($P, [string] $Message, [int] $At = -1, [int] $Length = 1)
    if ($At -lt 0) { $At = $P.P }
    $ex = New-Object System.FormatException $Message
    $ex.Data['PsdPos'] = $At
    $ex.Data['PsdLen'] = $Length
    throw $ex
}

function Skip-PsdSpace {
    param($P)
    $t = $P.T
    while ($P.P -lt $t.Length -and [char]::IsWhiteSpace($t[$P.P])) { $P.P++ }
}

function Test-PsdAt {
    param($P, [string] $S)
    ($P.P + $S.Length -le $P.T.Length) -and ([string]::CompareOrdinal($P.T, $P.P, $S, 0, $S.Length) -eq 0)
}

function Test-PsdWordAt {
    param($P, [string] $Word)
    $t = $P.T
    if ($P.P + $Word.Length -gt $t.Length) { return $false }
    if ([string]::Compare($t, $P.P, $Word, 0, $Word.Length, [System.StringComparison]::OrdinalIgnoreCase) -ne 0) { return $false }
    $next = $P.P + $Word.Length
    if ($next -lt $t.Length -and ([char]::IsLetterOrDigit($t[$next]) -or $t[$next] -eq '_')) { return $false }
    $true
}

function Get-PsdCharText {
    param($P)
    if ($P.P -ge $P.T.Length) { return 'the end' }
    "'" + $P.T[$P.P] + "'"
}

# The text of a regex match at this position, moving past it, or $null if it doesn't match here.
function Read-PsdMatch {
    param($P, [regex] $Rx)
    $m = $Rx.Match($P.T, $P.P)
    if (-not $m.Success) { return $null }
    $P.P += $m.Length
    $m.Value
}

function Read-PsdString {
    param($P)
    $t = $P.T
    $start = $P.P
    $P.P++
    $sb = New-Object System.Text.StringBuilder
    while ($true) {
        if ($P.P -ge $t.Length) { Stop-PsdParse $P 'this text is never closed. Add a " at the end of it.' $start ($t.Length - $start) }
        $c = $t[$P.P]
        if ($c -eq '"') {
            if ($P.P + 1 -lt $t.Length -and $t[$P.P + 1] -eq '"') { [void]$sb.Append('"'); $P.P += 2; continue }
            $P.P++
            break
        }
        [void]$sb.Append($c)
        $P.P++
    }
    $sb.ToString()
}

# Text of digits as a whole number: [int] if it fits, else [long].
function ConvertFrom-PsdIntText {
    param($P, [string] $Text, [int] $At)
    $n = [long]0
    if (-not [long]::TryParse($Text, [System.Globalization.NumberStyles]::AllowLeadingSign, $script:PsdInvariant, [ref]$n)) {
        Stop-PsdParse $P "the number $Text is too big." $At $Text.Length
    }
    if ($n -ge [int]::MinValue -and $n -le [int]::MaxValue) { return [int]$n }
    $n
}

# A number, true, false or null at this position as a Lit operand, or $null if there is none.
function Read-PsdLiteral {
    param($P)
    $start = $P.P
    $m = $script:PsdRxNumber.Match($P.T, $P.P)
    if ($m.Success) {
        $P.P += $m.Length
        if ($m.Groups[1].Success) { $v = [double]::Parse($m.Value, $script:PsdInvariant) }
        else { $v = ConvertFrom-PsdIntText $P $m.Value $start }
        return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
    }
    $w = Read-PsdMatch $P $script:PsdRxWord
    if ($null -eq $w) { return $null }
    @{ T = 'Lit'; V = @{ true = $true; false = $false }[$w]; Start = $start; End = $P.P }
}

function Read-PsdKey {
    param($P)
    $start = $P.P
    if (Test-PsdAt $P '"') { $k = Read-PsdString $P }
    else {
        $k = Read-PsdMatch $P $script:PsdRxName
        if ($null -eq $k) {
            if (Test-PsdAt $P '!') { Stop-PsdParse $P "a reference can't contain another !<...>. Write the key path directly: !<A.B>." }
            Stop-PsdParse $P "expected a key name here, but found $(Get-PsdCharText $P). Keys with spaces, dots or other signs go in double quotes: !<""my.key"">."
        }
    }
    @{ Key = $k; Index = 0; IsIndex = $false; Start = $start; End = $P.P }
}

function Read-PsdPath {
    param($P)
    $start = $P.P
    $path = @{ T = 'Path'; Ns = $null; Env = $null; Builtin = $null; Segs = (New-PsdList); Optional = $false; Start = $start; End = $start }

    if ($null -ne (Read-PsdMatch $P $script:PsdRxEnv)) {
        if (Test-PsdAt $P '"') { $path.Env = Read-PsdString $P }
        else {
            $path.Env = Read-PsdMatch $P $script:PsdRxEnvName
            if ($null -eq $path.Env) { Stop-PsdParse $P 'expected the name of an environment variable after env:.' }
        }
        $path.End = $P.P
        return $path
    }

    $ns = Read-PsdMatch $P $script:PsdRxNs
    if ($ns) { $path.Ns = $ns.Substring(0, $ns.Length - 2) }

    if (Test-PsdAt $P '@') {
        $P.P++
        $path.Builtin = Read-PsdMatch $P $script:PsdRxName
        if ($null -eq $path.Builtin) { Stop-PsdParse $P 'expected a built-in name after @, like @name or @dir.' }
        $path.End = $P.P
        return $path
    }

    $path.Segs.Add((Read-PsdKey $P))
    while ($true) {
        if (Test-PsdAt $P '.') {
            $P.P++
            $path.Segs.Add((Read-PsdKey $P))
        }
        elseif (Test-PsdAt $P '[') { $path.Segs.Add((Read-PsdIndex $P)) }
        else { break }
    }
    $path.End = $P.P
    $path
}

function Read-PsdIndex {
    param($P)
    $start = $P.P
    $P.P++
    Skip-PsdSpace $P
    $at = $P.P
    $n = Read-PsdMatch $P $script:PsdRxInt
    if ($null -eq $n) { Stop-PsdParse $P 'expected a number inside [ ], like [0] or [-1].' }
    $index = ConvertFrom-PsdIntText $P $n $at
    if ($index -isnot [int]) { Stop-PsdParse $P "the index $n is too big." $at $n.Length }
    Skip-PsdSpace $P
    if (-not (Test-PsdAt $P ']')) { Stop-PsdParse $P 'expected ] to close the index.' }
    $P.P++
    @{ Key = $null; Index = $index; IsIndex = $true; Start = $start; End = $P.P }
}

function Read-PsdOperand {
    param($P, [bool] $KeyFirst = $false)
    Skip-PsdSpace $P
    $start = $P.P
    if ($P.P -ge $P.T.Length) { Stop-PsdParse $P 'expected a key, text or a number here.' }
    if (Test-PsdAt $P '>') { Stop-PsdParse $P 'expected a key, text or a number here, but the reference ends.' }
    $optional = (Test-PsdAt $P '?') -and -not (Test-PsdAt $P '??')
    if ($optional) {
        $P.P++
        Skip-PsdSpace $P
    }
    else {
        if (-not $KeyFirst -and (Test-PsdAt $P '"')) {
            $v = Read-PsdString $P
            # "my.key".Sub and "my.key"[0] are quoted keys, not text.
            if (-not (Test-PsdAt $P '.') -and -not (Test-PsdAt $P '[')) { return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P } }
            $P.P = $start
        }
        $lit = Read-PsdLiteral $P
        if ($lit) { return $lit }
    }
    $path = Read-PsdPath $P
    $path.Optional = $optional
    $path.Start = $start
    $path
}

function Read-PsdExpr {
    param($P, [bool] $KeyFirst = $false)
    $start = $P.P
    $ops = New-PsdList
    $ops.Add((Read-PsdOperand $P $KeyFirst))
    while ($true) {
        Skip-PsdSpace $P
        if (-not (Test-PsdAt $P '??')) { break }
        $P.P += 2
        $ops.Add((Read-PsdOperand $P))
    }
    $filters = New-PsdList
    while ($true) {
        Skip-PsdSpace $P
        if (-not (Test-PsdAt $P '|')) { break }
        $filters.Add((Read-PsdFilter $P))
    }
    @{ T = 'Expr'; Ops = $ops; Filters = $filters; Start = $start; End = $P.P }
}

# Reads '| name' or '| name(a, b)' starting at the '|'.
function Read-PsdFilter {
    param($P)
    $start = $P.P
    $P.P++
    Skip-PsdSpace $P
    $name = Read-PsdMatch $P $script:PsdRxName
    if ($null -eq $name) { Stop-PsdParse $P 'expected a filter name after |, like | lower.' }
    $fargs = New-PsdList
    Skip-PsdSpace $P
    if (Test-PsdAt $P '(') {
        $P.P++
        Skip-PsdSpace $P
        if (Test-PsdAt $P ')') { $P.P++ }
        else {
            while ($true) {
                $fargs.Add((Read-PsdExpr $P))
                Skip-PsdSpace $P
                if (Test-PsdAt $P ',') { $P.P++; continue }
                if (Test-PsdAt $P ')') { $P.P++; break }
                Stop-PsdParse $P "expected , or ) in the arguments of '$name', but found $(Get-PsdCharText $P)."
            }
        }
    }
    @{ Name = $name; Args = $fargs; Start = $start; End = $P.P }
}

# Reads '!<' expr '>' starting at the '!<'. Returns a Ref part.
function Read-PsdRef {
    param($P)
    $start = $P.P
    $P.P += 2
    $e = Read-PsdExpr $P $true
    Skip-PsdSpace $P
    if (-not (Test-PsdAt $P '>')) {
        if ($P.P -ge $P.T.Length) { Stop-PsdParse $P 'this reference is never closed. Add a > at the end of it.' $start ($P.T.Length - $start) }
        Stop-PsdParse $P "this reference has $(Get-PsdCharText $P) where it should end. Close it with >, or use ?? or | to continue it."
    }
    $P.P++
    @{ T = 'Ref'; Expr = $e; Start = $start; End = $P.P; Raw = $P.T.Substring($start, $P.P - $start) }
}

# Splits a string into literal text and references. '!!<' is a literal '!<'.
function ConvertFrom-PsdTemplate {
    param([string] $Text)
    $parts = New-PsdList
    $p = New-PsdParser $Text
    $literal = ''
    $hasRef = $false
    while ($p.P -lt $Text.Length) {
        $at = $Text.IndexOf('!<', $p.P, [StringComparison]::Ordinal)
        if ($at -lt 0) { $literal += $Text.Substring($p.P); break }
        if ($at -gt $p.P -and $Text[$at - 1] -eq '!') {
            $literal += $Text.Substring($p.P, $at - 1 - $p.P) + '!<'
            $p.P = $at + 2
            continue
        }
        $literal += $Text.Substring($p.P, $at - $p.P)
        if ($literal) { $parts.Add($literal); $literal = '' }
        $p.P = $at
        $parts.Add((Read-PsdRef $p))
        $hasRef = $true
    }
    if ($literal) { $parts.Add($literal) }
    @{ Parts = $parts; HasRef = $hasRef }
}

# --- Conditions ---------------------------------------------------------------

function ConvertFrom-PsdCondition {
    param([string] $Text)
    $p = New-PsdParser $Text
    Skip-PsdSpace $p
    if ($p.P -ge $Text.Length) { Stop-PsdParse $p 'this !if has no condition. Write one after it, like ''!if !<Stage> -eq "prod"''.' }
    $c = Read-PsdOr $p
    Skip-PsdSpace $p
    if ($p.P -lt $Text.Length) {
        Stop-PsdParse $p "this condition has $(Get-PsdCharText $p) where it should end. Join conditions with -and or -or." $p.P ($Text.Length - $p.P)
    }
    $c
}

# Operands joined by one word, like a -and b -and c. Next is the function that reads an operand.
function Read-PsdChain {
    param($P, [string] $Word, [string] $Type, [string] $Next)
    $l = & $Next $P
    while ($true) {
        Skip-PsdSpace $P
        if (-not (Test-PsdWordAt $P $Word)) { return $l }
        $P.P += $Word.Length
        $l = @{ T = $Type; L = $l; R = (& $Next $P) }
    }
}

function Read-PsdOr {
    param($P)
    Read-PsdChain $P '-or' 'Or' 'Read-PsdAnd'
}

function Read-PsdAnd {
    param($P)
    Read-PsdChain $P '-and' 'And' 'Read-PsdNot'
}

function Read-PsdNot {
    param($P)
    Skip-PsdSpace $P
    if (Test-PsdWordAt $P '-not') {
        $P.P += 4
        $x = Read-PsdNot $P
        return @{ T = 'Not'; X = $x }
    }
    Read-PsdCompare $P
}

function Read-PsdCompare {
    param($P)
    Skip-PsdSpace $P
    if (Test-PsdAt $P '(') {
        $open = $P.P
        $P.P++
        $c = Read-PsdOr $P
        Skip-PsdSpace $P
        if (-not (Test-PsdAt $P ')')) { Stop-PsdParse $P 'this ( is never closed. Add a ) for it.' $open }
        $P.P++
        return $c
    }
    $start = $P.P
    $l = Read-PsdCondValue $P
    Skip-PsdSpace $P
    $m = $script:PsdRxCmpOp.Match($P.T, $P.P)
    if ($m.Success) {
        $op = $m.Value.ToLowerInvariant()
        $P.P += $m.Length
        $r = Read-PsdCondValue $P
        return @{ T = 'Cmp'; Op = $op; L = $l; R = $r; Start = $start; End = $P.P }
    }
    @{ T = 'Truth'; X = $l; Start = $start; End = $P.P }
}

function Read-PsdCondValue {
    param($P)
    Skip-PsdSpace $P
    $start = $P.P
    if (Test-PsdAt $P '!<') { return (Read-PsdRef $P) }
    if (Test-PsdAt $P '"') {
        $v = Read-PsdString $P
        return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
    }
    $lit = Read-PsdLiteral $P
    if ($lit) { return $lit }
    $n = $script:PsdRxName.Match($P.T, $P.P)
    if ($n.Success) {
        Stop-PsdParse $P "'$($n.Value)' needs to be a reference here: !<$($n.Value)>. Text in a condition goes in double quotes." $P.P $n.Length
    }
    Stop-PsdParse $P "expected a value here, but found $(Get-PsdCharText $P). Use a reference like !<Stage>, ""text"", a number, true, false or null."
}

# --- Paths given to commands --------------------------------------------------

function ConvertFrom-PsdPathText {
    param([string] $Text)
    $p = New-PsdParser $Text
    try {
        $path = Read-PsdPath $p
        if ($p.P -lt $Text.Length) { Stop-PsdParse $p "unexpected $(Get-PsdCharText $p)." }
        if ($path.Env -or $path.Ns -or $path.Builtin) { Stop-PsdParse $p 'a path here is just keys and indexes, like Server.Port or Plugins[0].' 0 }
    }
    catch [System.FormatException] {
        throw "'$Text' isn't a valid path: $($_.Exception.Message)"
    }
    , $path.Segs
}

function Format-PsdKeyText {
    param([string] $Key)
    if ($script:PsdRxPlainKey.IsMatch($Key)) { return $Key }
    '"' + $Key.Replace('"', '""') + '"'
}

function Join-PsdPath {
    param([string] $Path, $Key)
    if ($Key -is [int]) { return "$Path[$Key]" }
    $k = Format-PsdKeyText ([string]$Key)
    if ($Path) { return "$Path.$k" }
    $k
}

function Format-PsdSegs {
    param($Segs, [int] $Count = -1)
    if ($Count -lt 0) { $Count = $Segs.Count }
    $s = ''
    for ($i = 0; $i -lt $Count; $i++) {
        $seg = $Segs[$i]
        if ($seg.IsIndex) { $s = Join-PsdPath $s ([int]$seg.Index) } else { $s = Join-PsdPath $s $seg.Key }
    }
    $s
}
