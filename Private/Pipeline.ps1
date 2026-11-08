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

# Checks a merged document against the rules of a schema.
function Test-PsdDocSchema {
    param($Value, $Doc, $Rules, $Ctx, [bool] $Raw = $false)
    $rules = $Rules
    if ($null -eq $rules) { return }
    Test-PsdValueRule $Value $Doc.Tree $rules '' $Ctx $Doc
    if (-not $Raw) { return }
    foreach ($l in $Doc.Layers) {
        if ($l.File.Synthetic) { continue }
        $own = Get-PsdOwnTree $Doc $l.File
        $ov = Get-PsdNodeValue $own $Doc
        Test-PsdValueRule $ov $own $rules '' $Ctx $Doc -NoRequired
    }
}

# Loads a file or text. Returns @{ Ctx; Doc; Value; Entry }. Value is $null on errors.
function Invoke-PsdLoad {
    param(
        [string] $Path,
        [string] $Text,
        [string] $BasePath,
        [string] $Name = 'input',
        [string] $Schema,
        $Override,
        [System.Collections.IDictionary] $Include,
        [System.Collections.IDictionary] $Merge,
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

    # the schema is read before merging: Merge in it gives keys their default operator
    $rules = $null
    if (-not $SchemaMode) {
        $schemaPath = $null
        $schemaFrom = $null
        if ($Schema) { $schemaPath = Resolve-PsdUserPath $Schema }
        elseif ($entry.Schema) {
            $schemaPath = [IO.Path]::GetFullPath([IO.Path]::Combine($entry.Dir, $entry.Schema.Path))
            $schemaFrom = $entry.Schema.Node
        }
        if ($schemaPath) {
            $rules = Import-PsdSchemaRules $schemaPath $Ctx $schemaFrom
            if ($null -eq $rules) { return $result }
        }
    }
    $defaults = ConvertFrom-PsdMergeOption $Merge $Ctx
    if ($Ctx.Errors.Count -gt 0) { return $result }
    $doc = New-PsdFileDoc $entry $Ctx $Override -Prov:$Prov -Include $Include -Rules $rules -Defaults $defaults
    $result.Doc = $doc
    $value = Resolve-PsdDoc $doc
    if ($null -ne $rules -and $Ctx.Errors.Count -eq 0) {
        Test-PsdDocSchema $value $doc $rules $Ctx $Raw.IsPresent
    }
    if ($Ctx.Errors.Count -eq 0) { $result.Value = ConvertTo-PsdOutput $value }
    $result
}

function Resolve-PsdUserPath {
    param([string] $Path)
    $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    [IO.Path]::GetFullPath($p)
}
