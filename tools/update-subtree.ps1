<#
.SYNOPSIS
    Updates the branch <name> (lowercase module name) with the history of src/<Name> only.

.DESCRIPTION
    Other repositories can then include just the module with 'git subtree add' from that branch.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot

$sources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'src') -Directory)
if ($sources.Count -ne 1) { throw "Expected exactly one module folder in src/, found $($sources.Count)." }
$moduleName = $sources[0].Name

git -C $repoRoot subtree split "--prefix=src/$moduleName" "--branch=$($moduleName.ToLowerInvariant())"
if ($LASTEXITCODE -ne 0) { throw "git subtree split failed with exit code $LASTEXITCODE." }
