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

function Read-PsdNumber {
    param($P)
    $m = $script:PsdRxNumber.Match($P.T, $P.P)
    $P.P += $m.Length
    if ($m.Groups[1].Success) { return [double]::Parse($m.Value, $script:PsdInvariant) }
    $n = [long]::Parse($m.Value, $script:PsdInvariant)
    if ($n -ge [int]::MinValue -and $n -le [int]::MaxValue) { return [int]$n }
    $n
}

function Test-PsdNumberStart {
    param($P)
    $t = $P.T
    if ($P.P -ge $t.Length) { return $false }
    $c = $t[$P.P]
    if ([char]::IsDigit($c)) { return $true }
    ($c -eq '-') -and ($P.P + 1 -lt $t.Length) -and [char]::IsDigit($t[$P.P + 1])
}

function Read-PsdKey {
    param($P)
    $start = $P.P
    if ($P.P -lt $P.T.Length -and $P.T[$P.P] -eq '"') {
        $k = Read-PsdString $P
        return @{ Key = $k; Index = 0; IsIndex = $false; Start = $start; End = $P.P }
    }
    $m = $script:PsdRxName.Match($P.T, $P.P)
    if (-not $m.Success) {
        if ($P.P -lt $P.T.Length -and $P.T[$P.P] -eq '!') { Stop-PsdParse $P "a reference can't contain another !<...>. Write the key path directly: !<A.B>." }
        Stop-PsdParse $P "expected a key name here, but found $(Get-PsdCharText $P). Keys with spaces, dots or other signs go in double quotes: !<""my.key"">."
    }
    $P.P += $m.Length
    @{ Key = $m.Value; Index = 0; IsIndex = $false; Start = $start; End = $P.P }
}

function Read-PsdPath {
    param($P)
    $start = $P.P
    $path = @{ T = 'Path'; Ns = $null; Env = $null; Builtin = $null; Segs = (New-PsdList); Optional = $false; Start = $start; End = $start }
    $t = $P.T

    $m = $script:PsdRxEnv.Match($t, $P.P)
    if ($m.Success) {
        $P.P += 4
        if ($P.P -lt $t.Length -and $t[$P.P] -eq '"') { $path.Env = Read-PsdString $P }
        else {
            $n = $script:PsdRxEnvName.Match($t, $P.P)
            if (-not $n.Success) { Stop-PsdParse $P 'expected the name of an environment variable after env:.' }
            $path.Env = $n.Value
            $P.P += $n.Length
        }
        $path.End = $P.P
        return $path
    }

    $m = $script:PsdRxNs.Match($t, $P.P)
    if ($m.Success) {
        $path.Ns = $m.Groups[1].Value
        $P.P += $m.Length
    }

    if (Test-PsdAt $P '@') {
        $P.P++
        $n = $script:PsdRxName.Match($t, $P.P)
        if (-not $n.Success) { Stop-PsdParse $P 'expected a built-in name after @, like @name or @dir.' }
        $path.Builtin = $n.Value
        $P.P += $n.Length
        $path.End = $P.P
        return $path
    }

    $path.Segs.Add((Read-PsdKey $P))
    while ($P.P -lt $t.Length) {
        if ($t[$P.P] -eq '.') {
            $P.P++
            $path.Segs.Add((Read-PsdKey $P))
        }
        elseif ($t[$P.P] -eq '[') {
            $segStart = $P.P
            $P.P++
            Skip-PsdSpace $P
            $n = $script:PsdRxInt.Match($t, $P.P)
            if (-not $n.Success) { Stop-PsdParse $P 'expected a number inside [ ], like [0] or [-1].' }
            $P.P += $n.Length
            Skip-PsdSpace $P
            if (-not (Test-PsdAt $P ']')) { Stop-PsdParse $P 'expected ] to close the index.' }
            $P.P++
            $path.Segs.Add(@{ Key = $null; Index = [int]$n.Value; IsIndex = $true; Start = $segStart; End = $P.P })
        }
        else { break }
    }
    $path.End = $P.P
    $path
}

function Read-PsdOperand {
    param($P, [bool] $KeyFirst = $false)
    Skip-PsdSpace $P
    $start = $P.P
    $t = $P.T
    if ($P.P -ge $t.Length) { Stop-PsdParse $P 'expected a key, text or a number here.' }
    if ($t[$P.P] -eq '>') { Stop-PsdParse $P 'expected a key, text or a number here, but the reference ends.' }
    $optional = $false
    if ((Test-PsdAt $P '?') -and -not (Test-PsdAt $P '??')) {
        $optional = $true
        $P.P++
        Skip-PsdSpace $P
    }
    if (-not $optional) {
        if (-not $KeyFirst -and $P.P -lt $t.Length -and $t[$P.P] -eq '"') {
            $v = Read-PsdString $P
            if ($P.P -lt $t.Length -and ($t[$P.P] -eq '.' -or $t[$P.P] -eq '[')) { $P.P = $start }
            else { return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P } }
        }
        if ($P.P -eq $start -and (Test-PsdNumberStart $P)) {
            $v = Read-PsdNumber $P
            return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
        }
        $w = $script:PsdRxWord.Match($t, $P.P)
        if ($w.Success) {
            $P.P += $w.Length
            $v = $null
            switch ($w.Value.ToLowerInvariant()) { 'true' { $v = $true } 'false' { $v = $false } }
            return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
        }
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
        if (Test-PsdAt $P '??') {
            $P.P += 2
            $ops.Add((Read-PsdOperand $P))
        }
        else { break }
    }
    $filters = New-PsdList
    while ($true) {
        Skip-PsdSpace $P
        if (-not (Test-PsdAt $P '|')) { break }
        $fs = $P.P
        $P.P++
        Skip-PsdSpace $P
        $m = $script:PsdRxName.Match($P.T, $P.P)
        if (-not $m.Success) { Stop-PsdParse $P 'expected a filter name after |, like | lower.' }
        $name = $m.Value
        $P.P += $m.Length
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
        $filters.Add(@{ Name = $name; Args = $fargs; Start = $fs; End = $P.P })
    }
    @{ T = 'Expr'; Ops = $ops; Filters = $filters; Start = $start; End = $P.P }
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
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    $hasRef = $false
    while ($i -lt $Text.Length) {
        if ($Text[$i] -eq '!' -and $i + 2 -lt $Text.Length -and $Text[$i + 1] -eq '!' -and $Text[$i + 2] -eq '<') {
            [void]$sb.Append('!<')
            $i += 3
            continue
        }
        if ($Text[$i] -eq '!' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '<') {
            if ($sb.Length -gt 0) { $parts.Add($sb.ToString()); [void]$sb.Clear() }
            $p = New-PsdParser $Text $i
            $parts.Add((Read-PsdRef $p))
            $hasRef = $true
            $i = $p.P
            continue
        }
        [void]$sb.Append($Text[$i])
        $i++
    }
    if ($sb.Length -gt 0) { $parts.Add($sb.ToString()) }
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

function Read-PsdOr {
    param($P)
    $l = Read-PsdAnd $P
    while ($true) {
        Skip-PsdSpace $P
        if (Test-PsdWordAt $P '-or') { $P.P += 3; $r = Read-PsdAnd $P; $l = @{ T = 'Or'; L = $l; R = $r } }
        else { break }
    }
    $l
}

function Read-PsdAnd {
    param($P)
    $l = Read-PsdNot $P
    while ($true) {
        Skip-PsdSpace $P
        if (Test-PsdWordAt $P '-and') { $P.P += 4; $r = Read-PsdNot $P; $l = @{ T = 'And'; L = $l; R = $r } }
        else { break }
    }
    $l
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
    $t = $P.T
    if (Test-PsdAt $P '!<') { return (Read-PsdRef $P) }
    if ($P.P -lt $t.Length -and $t[$P.P] -eq '"') {
        $v = Read-PsdString $P
        return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
    }
    if (Test-PsdNumberStart $P) {
        $v = Read-PsdNumber $P
        return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
    }
    $w = $script:PsdRxWord.Match($t, $P.P)
    if ($w.Success) {
        $P.P += $w.Length
        $v = $null
        switch ($w.Value.ToLowerInvariant()) { 'true' { $v = $true } 'false' { $v = $false } }
        return @{ T = 'Lit'; V = $v; Start = $start; End = $P.P }
    }
    $n = $script:PsdRxName.Match($t, $P.P)
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
