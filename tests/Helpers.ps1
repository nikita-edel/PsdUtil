# Shared by the test files.

# Writes files into a new folder under TestDrive and returns the folder.
# Values can be text (written as UTF-8 without BOM) or byte arrays.
function New-TestFiles {
    param([hashtable] $Files)
    $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    foreach ($name in $Files.Keys) {
        $path = Join-Path $dir $name
        $parent = Split-Path $path -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $content = $Files[$name]
        if ($content -is [byte[]]) { [IO.File]::WriteAllBytes($path, $content) }
        else { [IO.File]::WriteAllText($path, [string]$content, (New-Object System.Text.UTF8Encoding $false)) }
    }
    $dir
}

# Runs a script block in a folder and returns the PSD codes of every error it produced.
function Get-ErrorCode {
    param([scriptblock] $Script, [string] $Dir)
    Push-Location $Dir
    try { $out = @(& $Script 2>&1 3>$null) }
    catch { $out = @($_) }
    finally { Pop-Location }
    foreach ($o in $out) {
        if ($o -is [System.Management.Automation.ErrorRecord]) { ($o.FullyQualifiedErrorId -split ',')[0] }
    }
}

# Compares two plain values exactly: same keys, same order of list items, same types.
function Compare-TestValue {
    param($Expected, $Actual, [string] $Path = '')
    if ($Expected -is [System.Collections.IDictionary]) {
        if ($Actual -isnot [System.Collections.IDictionary]) { return "$Path : expected a map" }
        foreach ($k in $Expected.PSBase.Keys) {
            if (-not $Actual.Contains($k)) { "$Path.$k : missing"; continue }
            Compare-TestValue $Expected[$k] $Actual[$k] "$Path.$k"
        }
        foreach ($k in $Actual.PSBase.Keys) { if (-not $Expected.Contains($k)) { "$Path.$k : unexpected" } }
        return
    }
    if ($Expected -is [array]) {
        if ($Actual -isnot [array]) { return "$Path : expected a list, got $Actual" }
        if ($Expected.Count -ne $Actual.Count) { return "$Path : expected $($Expected.Count) items, got $($Actual.Count)" }
        for ($i = 0; $i -lt $Expected.Count; $i++) { Compare-TestValue $Expected[$i] $Actual[$i] "$Path[$i]" }
        return
    }
    if ($null -eq $Expected) { if ($null -ne $Actual) { "$Path : expected `$null, got $Actual" }; return }
    if ($null -eq $Actual -or $Expected.GetType() -ne $Actual.GetType() -or -not $Expected.Equals($Actual)) {
        "$Path : expected $Expected, got $Actual"
    }
}
