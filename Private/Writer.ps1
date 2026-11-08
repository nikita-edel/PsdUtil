# Objects to .psd1 text.

$script:PsdFormatDefaults = [ordered]@{
    Indent         = 4
    Quote          = 'Single'
    SortKeys       = $false
    AlignEquals    = $false
    InlineArrayMax = 4
    LineEnding     = 'Auto'
    Bom            = $false
}
$script:PsdRxBareKey = New-Object regex '^[A-Za-z_][A-Za-z0-9_]*$'

function Get-PsdFormat {
    param([System.Collections.IDictionary] $Format, $Ctx)
    $f = [ordered]@{}
    foreach ($k in $script:PsdFormatDefaults.PSBase.Keys) { $f[$k] = $script:PsdFormatDefaults[$k] }
    if ($null -eq $Format) { return $f }
    foreach ($k in $Format.PSBase.Keys) {
        $name = [string]$k
        $v = $Format[$k]
        $known = $null
        foreach ($x in $script:PsdFormatDefaults.PSBase.Keys) { if ($x -ieq $name) { $known = $x } }
        if (-not $known) {
            Add-PsdError $Ctx 'PSD604' "'$name' isn't a format option." -Hint @((Get-PsdDidYouMean $name $script:PsdFormatDefaults.PSBase.Keys), "Options: $(@($script:PsdFormatDefaults.PSBase.Keys) -join ', ').")
            continue
        }
        $ok = switch ($known) {
            'Indent' { (Test-PsdNumber $v) -and $v -ge 0 -and $v -le 16 }
            'InlineArrayMax' { (Test-PsdNumber $v) -and $v -ge 0 }
            'Quote' { $v -in 'Single', 'Double' }
            'LineEnding' { $v -in 'Auto', 'LF', 'CRLF' }
            default { $v -is [bool] }
        }
        if (-not $ok) {
            $want = switch ($known) {
                'Indent' { 'a number from 0 to 16' } 'InlineArrayMax' { 'a number of 0 or more' }
                'Quote' { "'Single' or 'Double'" } 'LineEnding' { "'Auto', 'LF' or 'CRLF'" } default { '$true or $false' }
            }
            Add-PsdError $Ctx 'PSD604' "the format option $known has to be $want, but it's $(Format-PsdValueShort $v)."
            continue
        }
        $f[$known] = $v
    }
    $f
}

function Get-PsdNewLine {
    param($Format)
    switch ($Format.LineEnding) { 'LF' { return "`n" } 'CRLF' { return "`r`n" } }
    [Environment]::NewLine
}

function Format-PsdString {
    param([string] $Value, $Format, [bool] $Raw = $false)
    $v = $Value
    if (-not $Raw) { $v = $Value.Replace('!<', '!!<') }
    if ($Format.Quote -eq 'Double') {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($c in $v.ToCharArray()) {
            $code = [int]$c
            if ($c -eq '`' -or $c -eq '$' -or $c -eq '"' -or ($code -ge 0x201C -and $code -le 0x201E)) { [void]$sb.Append('`') }
            [void]$sb.Append($c)
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("'")
    foreach ($c in $v.ToCharArray()) {
        $code = [int]$c
        if ($c -eq "'" -or ($code -ge 0x2018 -and $code -le 0x201B)) { [void]$sb.Append($c) }
        [void]$sb.Append($c)
    }
    [void]$sb.Append("'")
    $sb.ToString()
}

function Format-PsdKeyOut {
    param($Key, $S)
    $k = $null
    if ($Key -is [string]) { $k = $Key }
    elseif ($Key -is [char] -or $Key -is [enum] -or (Test-PsdNumber $Key) -or $Key -is [guid]) { $k = Format-PsdScalarText $Key }
    if ($null -eq $k) {
        Add-PsdError $S.Ctx 'PSD603' "a key of type $($Key.GetType().Name) at $($S.Path) can't be written. Keys have to be text."
        return $null
    }
    $raw = [bool]$S['Raw']
    if (-not $raw) {
        if ($script:PsdRxOp.IsMatch($k)) {
            Add-PsdError $S.Ctx 'PSD603' "the key '$k' at $($S.Path) ends in a merge operator, so it would be read back as one."
            return $null
        }
        if ([regex]::IsMatch($k, '(?<!!)!<')) {
            Add-PsdError $S.Ctx 'PSD603' "the key '$k' at $($S.Path) contains !<, which keys can't have."
            return $null
        }
        if ($k.StartsWith('!')) { $k = '!' + $k }
    }
    if ($script:PsdRxBareKey.IsMatch($k)) { return $k }
    Format-PsdString $k @{ Quote = 'Single' } $raw
}

function Test-PsdScalarOut {
    param($Value)
    if ($null -eq $Value) { return $true }
    $Value -is [string] -or $Value -is [bool] -or (Test-PsdNumber $Value) -or $Value -is [char] -or $Value -is [enum] -or
    $Value -is [datetime] -or $Value -is [datetimeoffset] -or $Value -is [guid] -or $Value -is [version] -or $Value -is [uri] -or $Value -is [timespan]
}

function Format-PsdScalarOut {
    param($Value, $S)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' } return '$false' }
    if ($Value -is [string]) { return (Format-PsdString $Value $S.Format $S.Raw) }
    if ($Value -is [char]) { return (Format-PsdString ([string]$Value) $S.Format) }
    if ($Value -is [double] -or $Value -is [single]) {
        $d = [double]$Value
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) {
            Add-PsdError $S.Ctx 'PSD602' "$($S.Path) is $d, which a data file can't hold."
            return '$null'
        }
        $t = $d.ToString('R', $script:PsdInvariant)
        if ($t -notmatch '[.Ee]') { $t += '.0' }
        return $t
    }
    if ($Value -is [decimal]) { return $Value.ToString($script:PsdInvariant) + 'd' }
    if ($Value -is [long]) {
        $t = $Value.ToString($script:PsdInvariant)
        if ($Value -ge [int]::MinValue -and $Value -le [int]::MaxValue) { $t += 'l' }
        return $t
    }
    if (Test-PsdNumber $Value) { return $Value.ToString($null, $script:PsdInvariant) }
    if ($Value -is [enum]) { return (Format-PsdString $Value.ToString() $S.Format) }
    if ($Value -is [datetime]) { return (Format-PsdString $Value.ToString('o', $script:PsdInvariant) $S.Format) }
    if ($Value -is [datetimeoffset]) { return (Format-PsdString $Value.ToString('o', $script:PsdInvariant) $S.Format) }
    if ($Value -is [timespan]) { return (Format-PsdString $Value.ToString('c', $script:PsdInvariant) $S.Format) }
    Format-PsdString $Value.ToString() $S.Format
}

function Test-PsdSeen {
    param($S, $Value)
    foreach ($x in $S.Stack) { if ([object]::ReferenceEquals($x, $Value)) { return $true } }
    $false
}

# Turns any object into its parts: @{ Kind = 'map'|'list'|'scalar'; Pairs; Items; Value }.
function Split-PsdObject {
    param($Value, $S)
    if (Test-PsdScalarOut $Value) { return @{ Kind = 'scalar'; Value = $Value } }
    if ($Value -is [scriptblock] -or $Value -is [System.Security.SecureString] -or $Value -is [System.Management.Automation.PSCredential]) {
        Add-PsdError $S.Ctx 'PSD602' "$($S.Path) is a $($Value.GetType().Name), which a data file can't hold."
        return @{ Kind = 'scalar'; Value = $null }
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = New-PsdList
        foreach ($k in $Value.PSBase.Keys) { $pairs.Add(([object[]]($k, $Value[$k]))) }
        return @{ Kind = 'map'; Pairs = $pairs }
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = New-PsdList
        foreach ($x in $Value) { $items.Add($x) }
        return @{ Kind = 'list'; Items = $items }
    }
    $kept = Get-PsdKeptMap $Value
    if ($null -ne $kept) {
        $pairs = New-PsdList
        foreach ($k in $kept.PSBase.Keys) { $pairs.Add(([object[]]($k, $kept[$k]))) }
        return @{ Kind = 'map'; Pairs = $pairs; Raw = $true }
    }
    $base = $Value
    if ($Value -is [psobject]) { $base = $Value.PSObject.BaseObject }
    $isCustom = $Value -is [System.Management.Automation.PSCustomObject]
    $isClass = (-not $isCustom) -and $base.GetType().Assembly.IsDynamic
    $pairs = New-PsdList
    foreach ($p in $Value.PSObject.Properties) {
        if (-not $isCustom -and $p.MemberType -ne 'Property' -and $p.MemberType -ne 'NoteProperty') { continue }
        if (-not $p.IsGettable) { continue }
        $pv = $null
        try { $pv = $p.Value } catch { continue }
        if ($isClass -and $null -eq $pv) { continue }
        $pairs.Add(([object[]]($p.Name, $pv)))
    }
    if ($pairs.Count -eq 0 -and -not $isCustom -and -not $isClass) {
        $S.Ctx.Warnings.Add("$($S.Path) is a $($base.GetType().Name) with no properties, so it was written as text.")
        return @{ Kind = 'scalar'; Value = $Value.ToString() }
    }
    if ($isClass) { return @{ Kind = 'map'; Pairs = $pairs; Raw = $false } }
    @{ Kind = 'map'; Pairs = $pairs }
}

function Write-PsdValueText {
    param($Value, $S, [int] $Level)
    if ($Level -gt $S.Depth) {
        Add-PsdError $S.Ctx 'PSD601' "$($S.Path) is nested deeper than -Depth ($($S.Depth))." -Hint @('Raise -Depth if this is on purpose.')
        return '$null'
    }
    $parts = Split-PsdObject $Value $S
    if ($parts.Kind -eq 'scalar') { return (Format-PsdScalarOut $parts.Value $S) }
    if (Test-PsdSeen $S $Value) {
        Add-PsdError $S.Ctx 'PSD600' "$($S.Path) contains itself, so it can't be written." -Hint @("It points back to an object above it.")
        return '$null'
    }
    $S.Stack.Add($Value)
    $wasRaw = $S.Raw
    if ($parts.ContainsKey('Raw')) { $S.Raw = $parts.Raw }
    try {
        $f = $S.Format
        $nl = $S.NL
        $pad = ' ' * ($f.Indent * ($Level + 1))
        $endPad = ' ' * ($f.Indent * $Level)
        $here = $S.Path
        if ($parts.Kind -eq 'list') {
            $items = $parts.Items
            if ($items.Count -eq 0) { return '@()' }
            $allScalar = $true
            foreach ($x in $items) { if (-not (Test-PsdScalarOut $x)) { $allScalar = $false; break } }
            $texts = New-PsdList
            for ($i = 0; $i -lt $items.Count; $i++) {
                $S.Path = "$here[$i]"
                $texts.Add((Write-PsdValueText $items[$i] $S ($Level + 1)))
            }
            $S.Path = $here
            if ($allScalar -and $items.Count -le $f.InlineArrayMax) { return '@(' + ($texts -join ', ') + ')' }
            return '@(' + $nl + (($texts | ForEach-Object { $pad + $_ }) -join $nl) + $nl + $endPad + ')'
        }
        $pairs = $parts.Pairs
        if ($pairs.Count -eq 0) { return '@{}' }
        if ($f.SortKeys) {
            $pairs.Sort([Comparison[object]] { param($a, $b) [string]::Compare([string]$a[0], [string]$b[0], [StringComparison]::OrdinalIgnoreCase) })
        }
        $lines = New-PsdList
        $keys = New-PsdList
        foreach ($pr in $pairs) {
            $S.Path = Join-PsdPath $here ([string]$pr[0])
            $keys.Add((Format-PsdKeyOut $pr[0] $S))
        }
        $width = 0
        if ($f.AlignEquals) { foreach ($k in $keys) { if ($k -and $k.Length -gt $width) { $width = $k.Length } } }
        for ($i = 0; $i -lt $pairs.Count; $i++) {
            if ($null -eq $keys[$i]) { continue }
            $S.Path = Join-PsdPath $here ([string]$pairs[$i][0])
            $vt = Write-PsdValueText $pairs[$i][1] $S ($Level + 1)
            $lines.Add($pad + $keys[$i].PadRight($width) + ' = ' + $vt)
        }
        $S.Path = $here
        return '@{' + $nl + ($lines -join $nl) + $nl + $endPad + '}'
    }
    finally {
        $S.Stack.RemoveAt($S.Stack.Count - 1)
        $S.Raw = $wasRaw
    }
}

function ConvertTo-PsdTextInternal {
    param($Value, $Format, [int] $Depth, $Ctx)
    $S = @{ Ctx = $Ctx; Format = $Format; Depth = $Depth; Stack = (New-PsdList); Path = '(top)'; NL = (Get-PsdNewLine $Format); Raw = $false }
    Write-PsdValueText $Value $S 0
}

function Write-PsdTextFile {
    param([string] $Path, [string] $Text, [bool] $Bom, $Ctx)
    try {
        $enc = New-Object System.Text.UTF8Encoding $Bom
        [IO.File]::WriteAllText($Path, $Text, $enc)
        return $true
    }
    catch {
        Add-PsdError $Ctx 'PSD605' "the file $Path can't be written: $($_.Exception.InnerException.Message)"
        return $false
    }
}
