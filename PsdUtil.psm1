# Root module: loads every function from Private/ and Public/.
# Only the functions listed in FunctionsToExport of the manifest are visible to users.

Set-StrictMode -Version Latest

foreach ($folder in @('Private', 'Public')) {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -Recurse | Sort-Object -Property FullName)) {
        . $file.FullName
    }
}
