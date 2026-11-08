# Shared setup for all Pester tests. Dot-source it from BeforeAll, for a test file one folder below tests/:
#
#   BeforeAll { . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'TestHelpers.ps1') }
#
# It imports the module under test from src/ and sets $TestRepoRoot, $TestManifest and $TestModuleName.
# Test files must stay ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).

$script:TestRepoRoot = Split-Path -Parent $PSScriptRoot
$script:TestManifest = @(Get-ChildItem -Path (Join-Path -Path $script:TestRepoRoot -ChildPath 'src/*/*.psd1'))[0].FullName
$script:TestModuleName = [System.IO.Path]::GetFileNameWithoutExtension($script:TestManifest)

# A copy from elsewhere (the installed module, loaded by a profile) must go: Pester refuses two modules of one name.
$testModuleFolder = Split-Path -Parent $script:TestManifest
Get-Module -Name $script:TestModuleName | Where-Object { -not $_.Path.StartsWith($testModuleFolder) } | Remove-Module -Force
if ($null -eq (Get-Module -Name $script:TestModuleName)) { Import-Module -Name $script:TestManifest -Force -ErrorAction Stop }

$script:Examples = Join-Path -Path $PSScriptRoot -ChildPath 'examples'

function Import-Text {
    param([string] $Text, [hashtable] $More = @{}, [hashtable] $Params = @{})
    $files = @{ 'main.psd1' = $Text }
    foreach ($k in $More.Keys) { $files[$k] = $More[$k] }
    $dir = New-TestFiles $files
    Import-Psd (Join-Path $dir 'main.psd1') @Params
}

function Get-ExpectedResult {
    param([string] $Folder)
    $dir = [IO.Path]::GetFullPath((Join-Path $Examples $Folder))
    $text = [IO.File]::ReadAllText((Join-Path $dir 'result.psd1')).Replace('C:/app/config', $dir.Replace('\', '/'))
    $file = Join-Path $TestDrive "expected-$Folder.psd1"
    [IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $true))
    $expected = Import-PowerShellDataFile $file
    # $IsWindows doesn't exist on 5.1, so the version check has to come first.
    $os = 'linux'
    if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) { $os = 'windows' } elseif ($IsMacOS) { $os = 'macos' }
    if ($expected.Contains('Builtins')) {
        $expected.Builtins.Os = $os
        if ($os -ne 'windows') { $expected.Checks.Remove('Os') }
    }
    $expected
}

function Get-ErrorText {
    param([scriptblock] $Script, [string] $Dir)
    Push-Location $Dir
    try { $records = @(& $Script 2>&1 3>$null) }
    finally { Pop-Location }
    foreach ($r in $records) {
        if ($r -is [System.Management.Automation.ErrorRecord]) { $r.Exception.Message }
    }
}
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
