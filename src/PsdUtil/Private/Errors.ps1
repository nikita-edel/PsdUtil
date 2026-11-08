# Context, error collection, message format, and small shared helpers.

$script:PsdIsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$script:PsdNextId = 0
$script:PsdInvariant = [System.Globalization.CultureInfo]::InvariantCulture
$script:PsdDefaultLimits = [ordered]@{
    MaxDepth        = 64
    MaxFiles        = 256
    MaxFileSize     = 100MB
    MaxStringLength = 1MB
    MaxNodes        = 100000
    RegexTimeout    = 1
}

function New-PsdContext {
    param(
        [System.Collections.IDictionary] $Limits,
        [string] $Unresolved = 'Error'
    )
    $l = Copy-PsdPlain $script:PsdDefaultLimits
    if ($Limits) {
        foreach ($k in $Limits.PSBase.Keys) {
            $name = [string]$k
            if (-not $l.Contains($name)) {
                throw "'$name' isn't a limit. Limits: $(@($script:PsdDefaultLimits.PSBase.Keys) -join ', ')."
            }
            $value = $Limits[$k]
            if ($name -eq 'RegexTimeout' -and $value -is [timespan]) { $value = $value.TotalSeconds }
            if (-not (Test-PsdNumber $value) -or $value -le 0) {
                throw "The limit '$name' has to be a number above 0."
            }
            $l[$name] = $value
        }
    }
    @{
        Errors     = New-PsdList
        Warnings   = New-PsdList
        # where a value came from when it could have come from more than one place; written with -Verbose
        Notes      = New-PsdList
        NoteSeen   = @{}
        # -Loader: reads files that aren't .psd1, like .ps1 scripts; PsdUtil itself runs no code
        Loader     = $null
        Limits     = $l
        Files      = @{}
        Docs       = @{}
        DocStack   = New-PsdList
        Unresolved = $Unresolved
        Nodes      = 0
        SchemaMode = $false
        Trace      = $null
        LimitHit   = $false
        Seen       = @{}
    }
}

function New-PsdId {
    $script:PsdNextId++
    $script:PsdNextId
}

function Add-PsdError {
    param(
        $Ctx,
        [string] $Code,
        [string] $Message,
        $File = $null,
        [int] $Line = 0,
        [int] $Column = 0,
        [int] $Length = 0,
        [string] $Key = $null,
        [string[]] $Hint = @(),
        [string[]] $Extra = @()
    )
    # The same problem can be reached twice (a shared file, a cached value). Report it once.
    $fileText = if ($File) { $File.Path } else { '' }
    $sig = '{0}|{1}|{2}|{3}|{4}' -f $Code, $fileText, $Line, $Column, $Message
    if ($Ctx.Seen.ContainsKey($sig)) { return }
    $Ctx.Seen[$sig] = $true
    $Ctx.Errors.Add(@{
            Code    = $Code
            Message = $Message
            File    = $File
            Line    = $Line
            Column  = $Column
            Length  = $Length
            Key     = $Key
            Hint    = $Hint
            Extra   = $Extra
        })
}

function Add-PsdLimitError {
    param($Ctx, [string] $Limit, [string] $Where, $Node = $null)
    $Ctx.LimitHit = $true
    $loc = Get-PsdNodeLoc $Node
    Add-PsdError $Ctx 'PSD700' "the limit $Limit ($($Ctx.Limits[$Limit])) was reached $Where." -File $loc.File -Line $loc.Line -Column $loc.Col `
        -Hint @("If this is on purpose, raise it: -Limits @{ $Limit = ... }")
}

function Format-PsdErrorText {
    param($Info)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $head = $Info.Message
    if ($Info.File) {
        $leaf = $Info.File.Name + $Info.File.Ext
        if ($Info.File.Synthetic) { $leaf = $Info.File.Label }
        if ($Info.Line -gt 0) { $head = "$leaf, line $($Info.Line): $head" } else { $head = "${leaf}: $head" }
    }
    elseif ($head.Length -gt 0) { $head = $head.Substring(0, 1).ToUpperInvariant() + $head.Substring(1) }
    $lines.Add($head)

    $body = New-Object 'System.Collections.Generic.List[string]'
    if ($Info.File -and $Info.Line -gt 0 -and $Info.File.Lines -and $Info.Line -le $Info.File.Lines.Count) {
        $src = $Info.File.Lines[$Info.Line - 1].TrimEnd()
        $trimmed = $src.TrimStart()
        $lead = $src.Length - $trimmed.Length
        $body.Add('    ' + $trimmed)
        if ($Info.Column -gt 0) {
            $offset = [Math]::Max(0, $Info.Column - 1 - $lead)
            $len = [Math]::Max(1, $Info.Length)
            if ($offset + $len -gt $trimmed.Length) { $len = [Math]::Max(1, $trimmed.Length - $offset) }
            $body.Add('    ' + (' ' * $offset) + ('^' * $len))
        }
    }
    foreach ($x in $Info.Extra) { $body.Add('    ' + $x) }
    foreach ($h in $Info.Hint) { if ($h) { $body.Add('    ' + $h) } }

    if ($body.Count -gt 0) {
        $lines.Add('')
        foreach ($b in $body) { $lines.Add($b) }
    }
    $code = "[$($Info.Code)]"
    $last = $lines[$lines.Count - 1]
    if ($last.Length + 2 + $code.Length -le 76) { $last = $last.PadRight(76 - $code.Length) + $code }
    else { $last = $last + '  ' + $code }
    $lines[$lines.Count - 1] = $last
    $lines -join [Environment]::NewLine
}

function ConvertTo-PsdErrorObject {
    param($Info)
    [pscustomobject]@{
        PSTypeName = 'PsdUtil.Error'
        Code       = $Info.Code
        File       = $(if ($Info.File) { $Info.File.Path })
        Line       = $Info.Line
        Column     = $Info.Column
        Key        = $Info.Key
        Message    = Format-PsdErrorText $Info
    } | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Message } -Force -PassThru
}

function New-PsdErrorRecord {
    param($Info)
    $ex = New-Object System.Exception (Format-PsdErrorText $Info)
    New-Object System.Management.Automation.ErrorRecord $ex, $Info.Code, ([System.Management.Automation.ErrorCategory]::InvalidData), (ConvertTo-PsdErrorObject $Info)
}

# Writes every collected error and warning through the calling command.
function Write-PsdResult {
    param($Cmdlet, $Ctx, [string] $What)
    foreach ($n in $Ctx.Notes) { $Cmdlet.WriteVerbose($n) }
    foreach ($w in $Ctx.Warnings) { $Cmdlet.WriteWarning($w) }
    foreach ($e in $Ctx.Errors) { $Cmdlet.WriteError((New-PsdErrorRecord $e)) }
    if ($Ctx.Errors.Count -gt 1 -and $What) {
        $Cmdlet.WriteWarning("Found $($Ctx.Errors.Count) problems in $What. Nothing was loaded.")
    }
}

# --- Suggestions --------------------------------------------------------------

function Get-PsdDistance {
    param([string] $First, [string] $Second)
    # Edit distance where swapping two neighbouring letters counts as one edit.
    $s = $First.ToLowerInvariant(); $t = $Second.ToLowerInvariant()
    $n = $s.Length; $m = $t.Length
    $w = $m + 1
    $d = New-Object 'int[]' (($n + 1) * $w)
    for ($i = 0; $i -le $n; $i++) { $d[$i * $w] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = 1
            if ($s[$i - 1] -eq $t[$j - 1]) { $cost = 0 }
            $up = $d[($i - 1) * $w + $j] + 1
            $left = $d[$i * $w + $j - 1] + 1
            $diag = $d[($i - 1) * $w + $j - 1] + $cost
            $v = [Math]::Min([Math]::Min($up, $left), $diag)
            if ($i -gt 1 -and $j -gt 1 -and $s[$i - 1] -eq $t[$j - 2] -and $s[$i - 2] -eq $t[$j - 1]) {
                $swap = $d[($i - 2) * $w + $j - 2] + 1
                $v = [Math]::Min($v, $swap)
            }
            $d[$i * $w + $j] = $v
        }
    }
    $d[$n * $w + $m]
}

function Get-PsdDidYouMean {
    param([string] $Word, $Candidates)
    $best = $null; $bestD = [int]::MaxValue
    $limit = [Math]::Max(2, [int][Math]::Floor($Word.Length / 3))
    foreach ($c in $Candidates) {
        $s = [string]$c
        if ($s -eq $Word) { continue }
        $dist = Get-PsdDistance $Word $s
        if ($dist -lt $bestD) { $bestD = $dist; $best = $s }
    }
    if ($best -and $bestD -le $limit) { "Did you mean '$best'?" }
}

# --- Values -------------------------------------------------------------------

function Test-PsdNumber {
    param($Value)
    $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or
    $Value -is [single] -or $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
    $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]
}

function Test-PsdList {
    param($Value)
    ($Value -is [System.Collections.IList]) -and ($Value -isnot [string])
}

function Test-PsdContainer {
    param($Value)
    ($Value -is [System.Collections.IDictionary]) -or (Test-PsdList $Value)
}

function Get-PsdKindText {
    param($Value)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [string]) { return 'text' }
    if ($Value -is [bool]) { return 'true or false' }
    if (Test-PsdNumber $Value) { return 'a number' }
    if ($Value -is [System.Collections.IDictionary]) { return 'a map' }
    if (Test-PsdList $Value) { return 'a list' }
    'a ' + $Value.GetType().Name
}

function Format-PsdScalarText {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [double]) { return $Value.ToString('R', $script:PsdInvariant) }
    if ($Value -is [System.IFormattable]) { return $Value.ToString($null, $script:PsdInvariant) }
    [string]$Value
}

function Format-PsdValueShort {
    param($Value)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [string]) { return "'$Value'" }
    if ($Value -is [bool]) { if ($Value) { return '$true' } return '$false' }
    if (Test-PsdNumber $Value) { return (Format-PsdScalarText $Value) }
    Get-PsdKindText $Value
}

# Equality for list operators, unique, -in, Enum and Compare-Psd. Text ignores case unless told otherwise.
function Test-PsdEqual {
    param($A, $B, [System.StringComparison] $Text = 'OrdinalIgnoreCase')
    if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
    if ($A -is [System.Collections.IDictionary]) {
        if ($B -isnot [System.Collections.IDictionary] -or $A.PSBase.Count -ne $B.PSBase.Count) { return $false }
        foreach ($k in $A.PSBase.Keys) {
            if (-not $B.Contains($k) -or -not (Test-PsdEqual $A[$k] $B[$k] $Text)) { return $false }
        }
        return $true
    }
    if (Test-PsdList $A) {
        if (-not (Test-PsdList $B) -or $A.Count -ne $B.Count) { return $false }
        for ($i = 0; $i -lt $A.Count; $i++) { if (-not (Test-PsdEqual $A[$i] $B[$i] $Text)) { return $false } }
        return $true
    }
    if ($A -is [string] -and $B -is [string]) { return [string]::Equals($A, $B, $Text) }
    if ((Test-PsdNumber $A) -and (Test-PsdNumber $B)) { return ([double]$A -eq [double]$B) }
    if ($A.GetType() -ne $B.GetType()) { return $false }
    $A.Equals($B)
}

function Test-PsdListHas {
    param($List, $Item)
    foreach ($x in $List) { if (Test-PsdEqual $x $Item) { return $true } }
    $false
}

function New-PsdList {
    New-Object 'System.Collections.Generic.List[object]'
}

# A new list: the items of List ($null is fine), then Item.
function Join-PsdList {
    param($List, $Item)
    $out = New-PsdList
    foreach ($x in $List) { $out.Add($x) }
    $out.Add($Item)
    , $out
}

# What can stand for a whole file or map: a map, a PSCustomObject or a generated class made from a map.
function Test-PsdMapLike {
    param($Value)
    $Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject] -or $null -ne (Get-PsdKeptMap $Value)
}

function New-PsdRegex {
    param([string] $Pattern, $Ctx, [switch] $CaseSensitive)
    $opt = [System.Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
    if ($CaseSensitive) { $opt = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant }
    New-Object System.Text.RegularExpressions.Regex $Pattern, $opt, ([timespan]::FromSeconds($Ctx.Limits.RegexTimeout))
}

function Get-PsdPathKey {
    param([string] $Full)
    if ($script:PsdIsWindows) { return $Full.ToLowerInvariant() }
    $Full
}

function ConvertTo-PsdSlashPath {
    param([string] $Path)
    $Path.Replace('\', '/')
}

function Get-PsdOsName {
    if ($script:PsdIsWindows) { return 'windows' }
    $mac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction Ignore
    if ($mac) { return 'macos' }
    'linux'
}

# The items of a list as a new list, or a one-item list. @($list) fails on generic lists.
function Get-PsdItems {
    param($Value)
    $out = New-PsdList
    if (Test-PsdList $Value) { foreach ($x in $Value) { $out.Add($x) } }
    else { $out.Add($Value) }
    , $out
}
