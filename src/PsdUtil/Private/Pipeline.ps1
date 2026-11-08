# The full load: read, chain, merge, resolve, validate. Shared by the public commands.

function ConvertTo-PsdOutput {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($k in $Value.PSBase.Keys) { $out[$k] = ConvertTo-PsdOutput $Value[$k] }
        return , $out
    }
    if (Test-PsdList $Value) {
        $arr = New-Object 'object[]' $Value.Count
        for ($i = 0; $i -lt $Value.Count; $i++) { $arr[$i] = ConvertTo-PsdOutput $Value[$i] }
        return , $arr
    }
    , $Value
}

function Resolve-PsdDoc {
    param($Doc)
    $v = Get-PsdNodeValue $Doc.Tree $Doc
    # Included documents are checked too, even the parts nothing reads.
    foreach ($d in @($Doc.Ctx.Docs.Values)) { $null = Get-PsdNodeValue $d.Tree $d }
    , $v
}

# Loads a file or text. Returns @{ Ctx; Doc; Value; Entry }. Value is $null on errors.
function Invoke-PsdLoad {
    param(
        [string] $Path,
        [string] $Text,
        [string] $BasePath,
        [string] $Name = 'input',
        [string] $Schema,
        [System.Collections.IDictionary] $Override,
        [string] $Unresolved = 'Error',
        [System.Collections.IDictionary] $Limits,
        [switch] $Raw,
        [switch] $Prov,
        [switch] $SchemaMode,
        $Ctx = $null
    )
    if ($null -eq $Ctx) { $Ctx = New-PsdContext -Limits $Limits -Unresolved $Unresolved }
    $Ctx.SchemaMode = $SchemaMode.IsPresent
    $result = @{ Ctx = $Ctx; Doc = $null; Value = $null; Entry = $null }
    if ($PSBoundParameters.ContainsKey('Text')) {
        if (-not $BasePath) { $BasePath = (Get-Location -PSProvider FileSystem).ProviderPath }
        $entry = ConvertFrom-PsdText $Text ([IO.Path]::Combine([IO.Path]::GetFullPath($BasePath), "$Name.psd1")) $Ctx
    }
    else {
        $full = Resolve-PsdUserPath $Path
        $entry = Read-PsdFile $full $Ctx
    }
    $result.Entry = $entry
    if ($null -eq $entry -or $null -eq $entry.Root) { return $result }
    $doc = New-PsdFileDoc $entry $Ctx $Override -Prov:$Prov
    $result.Doc = $doc
    $value = Resolve-PsdDoc $doc

    $schemaPath = $null
    $schemaFrom = $null
    if ($Schema) { $schemaPath = Resolve-PsdUserPath $Schema }
    elseif ($entry.Schema) {
        $schemaPath = [IO.Path]::GetFullPath([IO.Path]::Combine($entry.Dir, $entry.Schema.Path))
        $schemaFrom = $entry.Schema.Node
    }
    if ($schemaPath -and -not $SchemaMode -and $Ctx.Errors.Count -eq 0) {
        $rules = Import-PsdSchemaRules $schemaPath $Ctx $schemaFrom
        if ($null -ne $rules) {
            Test-PsdValueRule $value $doc.Tree $rules '' $Ctx $doc
            if ($Raw) {
                foreach ($l in $doc.Layers) {
                    if ($l.File.Synthetic) { continue }
                    $own = Get-PsdOwnTree $doc $l.File
                    $ov = Get-PsdNodeValue $own $doc
                    Test-PsdValueRule $ov $own $rules '' $Ctx $doc -NoRequired
                }
            }
        }
    }
    if ($Ctx.Errors.Count -eq 0) { $result.Value = ConvertTo-PsdOutput $value }
    $result
}

function Resolve-PsdUserPath {
    param([string] $Path)
    $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [IO.Path]::GetFullPath($p)
}
