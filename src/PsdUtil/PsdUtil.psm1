# Root module: loads every function from Private/ and Public/.
# Only the functions listed in FunctionsToExport of the manifest are visible to users.

Set-StrictMode -Version Latest

foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/Private", "$PSScriptRoot/Public" -Filter '*.ps1' -Recurse) {
    . $file.FullName
}
