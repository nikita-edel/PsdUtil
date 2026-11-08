using namespace System.Management.Automation.Language

# Schemas: .psd1 files loaded like any other file, then turned into rules.

$script:PsdKeywords = @('Type', 'Required', 'Description', 'Default', 'Enum', 'Pattern', 'Min', 'Max', 'Properties', 'Items', 'AllowUnknown', 'Merge')
$script:PsdBaseTypes = @('string', 'int', 'double', 'bool', 'map', 'array', 'any', 'null')

function Find-PsdTreeNode {
    param($Tree, $Keys)
    $cur = $Tree
    foreach ($k in $Keys) {
        if ($null -eq $cur -or $cur.K -ne 'M' -or -not $cur.V.Contains($k)) { return $cur }
        $cur = $cur.V[$k]
    }
    $cur
}

function Read-PsdEnumFile {
    param([string] $Path, $Ctx, $From)
    $out = New-PsdList
    if (-not [IO.File]::Exists($Path)) {
        Add-PsdNodeError $Ctx 'PSD514' "the types file $Path doesn't exist." $From
        return , $out
    }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseInput($text, $Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Add-PsdNodeError $Ctx 'PSD514' "the types file $Path can't be read: $($errors[0].Message)" $From
        return , $out
    }
    foreach ($t in $ast.FindAll({ param($a) $a -is [TypeDefinitionAst] -and $a.IsEnum }, $true)) {
        $members = New-PsdList
        $defs = New-PsdList
        foreach ($m in $t.Members) {
            $members.Add($m.Name)
            if ($m.InitialValue) { $defs.Add("$($m.Name) = $($m.InitialValue.Extent.Text)") } else { $defs.Add($m.Name) }
        }
        $attrs = ''
        foreach ($a in $t.Attributes) { $attrs += $a.Extent.Text + ' ' }
        $out.Add(@{ Name = $t.Name; Members = $members; Text = "${attrs}enum $($t.Name) { $($defs -join '; ') }"; Source = $Path; Flags = ($attrs -match 'Flags') })
    }
    , $out
}

function Import-PsdSchemaRules {
    param([string] $Path, $Ctx, $From)
    if (-not [IO.File]::Exists($Path)) {
        Add-PsdNodeError $Ctx 'PSD511' "the schema file $Path doesn't exist." $From
        return $null
    }
    $sctx = New-PsdContext -Limits $Ctx.Limits
    $r = Invoke-PsdLoad -Path $Path -Ctx $sctx -SchemaMode
    foreach ($e in $sctx.Errors) { $Ctx.Errors.Add($e) }
    if ($sctx.Errors.Count -gt 0) { return $null }

    $enums = @{}
    foreach ($f in @($sctx.Files.Values)) {
        foreach ($t in $f.Types) {
            $p = [IO.Path]::GetFullPath([IO.Path]::Combine($f.Dir, $t.Path))
            foreach ($e in (Read-PsdEnumFile $p $Ctx $t.Node)) {
                if ($enums.ContainsKey($e.Name) -and $enums[$e.Name].Source -ne $e.Source) {
                    Add-PsdNodeError $Ctx 'PSD515' "the enum $($e.Name) is in two types files: $($enums[$e.Name].Source) and $($e.Source)." $t.Node
                    continue
                }
                $enums[$e.Name] = $e
            }
        }
    }
    $s = @{ Ctx = $Ctx; Doc = $r.Doc; Enums = $enums; File = $r.Entry }
    $before = $Ctx.Errors.Count
    $rule = New-PsdRule $r.Value (New-PsdList) $s $true
    if ($Ctx.Errors.Count -gt $before) { return $null }
    $rule.SchemaFile = $r.Entry
    $rule
}

function Add-PsdSchemaError {
    param($S, [string] $Code, [string] $Message, $Keys, [string[]] $Hint = @())
    $node = Find-PsdTreeNode $S.Doc.Tree $Keys
    if ($node -and $node.Line -gt 0) { Add-PsdNodeError $S.Ctx $Code $Message $node -Hint $Hint }
    else { Add-PsdError $S.Ctx $Code $Message -File $S.File -Hint $Hint }
}

function Get-PsdRuleName {
    param($Keys)
    $parts = New-PsdList
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        if ($Keys[$i] -eq 'Properties' -and $i + 1 -lt $Keys.Count) { $parts.Add($Keys[$i + 1]); $i++ }
        elseif ($Keys[$i] -eq 'Items') { $parts.Add('[items]') }
    }
    if ($parts.Count -eq 0) { return 'the schema' }
    ($parts -join '.').Replace('.[items]', '[items]')
}

function ConvertFrom-PsdTypeText {
    param([string] $Text, $S, $Keys)
    $t = $Text.Trim()
    $list = $false
    if ($t.EndsWith('[]')) { $list = $true; $t = $t.Substring(0, $t.Length - 2) }
    $spec = @{ Name = $t; List = $list; Kind = 'base'; Members = $null; Source = $null; Def = $null; DotNet = $null; Text = $Text.Trim() }
    if ($t -match '^\[(.+)\]$') {
        $n = $Matches[1]
        if ($S.Enums.ContainsKey($n)) {
            $e = $S.Enums[$n]
            $spec.Kind = 'enum'; $spec.Name = $e.Name; $spec.Members = $e.Members; $spec.Source = $e.Source; $spec.Def = $e.Text
            return $spec
        }
        if ($n -match '^(system\.)?(version|guid|datetime)$') {
            $spec.Kind = 'conv'
            $spec.Name = $Matches[2].ToLowerInvariant()
            return $spec
        }
        $type = $n -as [type]
        if ($type -and $type.IsEnum) {
            $spec.Kind = 'enum'; $spec.Name = $n; $spec.DotNet = $type.FullName
            $spec.Members = New-PsdList
            foreach ($x in [enum]::GetNames($type)) { $spec.Members.Add($x) }
            return $spec
        }
        $known = @($S.Enums.PSBase.Keys)
        $hint = @((Get-PsdDidYouMean $n $known), "Your own enums need '!types' = './Types.psm1' in the schema.")
        Add-PsdSchemaError $S 'PSD513' "[$n] isn't a known enum or supported type." $Keys $hint
        return $null
    }
    $lower = $t.ToLowerInvariant()
    if ($script:PsdBaseTypes -contains $lower) { $spec.Name = $lower; return $spec }
    Add-PsdSchemaError $S 'PSD509' "'$t' isn't a type." $Keys @((Get-PsdDidYouMean $t $script:PsdBaseTypes), "Types: $($script:PsdBaseTypes -join ', '), or an enum like '[LogLevel]'.")
    $null
}

function New-PsdRule {
    param($Value, $Keys, $S, [bool] $IsRoot)
    $rule = @{
        Types = New-PsdList; Required = $false; Description = $null; Default = $null; HasDefault = $false
        Enum = $null; Pattern = $null; Regex = $null; Min = $null; Max = $null
        Properties = $null; Items = $null; AllowUnknown = $false; Name = (Get-PsdRuleName $Keys); SchemaFile = $null
        Merge = $null
    }
    if ($Value -is [string]) { $Value = @{ Type = $Value } }
    if ($Value -isnot [System.Collections.IDictionary]) {
        Add-PsdSchemaError $S 'PSD500' "the rule for $($rule.Name) has to be a type like 'int', or a map like @{ Type = 'int' }." $Keys
        return $rule
    }
    $sub = { param($name) Join-PsdList $Keys $name }
    foreach ($k in $Value.PSBase.Keys) {
        if ($script:PsdKeywords -inotcontains $k) {
            Add-PsdSchemaError $S 'PSD500' "'$k' isn't a schema keyword (in $($rule.Name))." (& $sub $k) @((Get-PsdDidYouMean $k $script:PsdKeywords), "Keywords: $($script:PsdKeywords -join ', ').")
        }
    }

    if ($Value.Contains('Type')) {
        foreach ($x in @($Value['Type'])) {
            if ($x -isnot [string]) { Add-PsdSchemaError $S 'PSD500' "Type in $($rule.Name) has to be a type name or a list of them." (& $sub 'Type'); continue }
            $spec = ConvertFrom-PsdTypeText $x $S (& $sub 'Type')
            if ($spec) { $rule.Types.Add($spec) }
        }
    }
    elseif ($IsRoot) { $rule.Types.Add((ConvertFrom-PsdTypeText 'map' $S $Keys)) }

    foreach ($flag in 'Required', 'AllowUnknown') {
        if ($Value.Contains($flag)) {
            $x = $Value[$flag]
            if ($x -isnot [bool]) { Add-PsdSchemaError $S 'PSD500' "$flag in $($rule.Name) has to be `$true or `$false." (& $sub $flag) }
            else { $rule[$flag] = $x }
        }
    }
    if ($Value.Contains('Description')) { $rule.Description = [string]$Value['Description'] }
    if ($Value.Contains('Enum')) {
        $rule.Enum = New-PsdList
        foreach ($x in @($Value['Enum'])) { $rule.Enum.Add($x) }
    }
    if ($Value.Contains('Pattern')) {
        $rule.Pattern = [string]$Value['Pattern']
        try { $rule.Regex = New-PsdRegex $rule.Pattern $S.Ctx -CaseSensitive }
        catch { Add-PsdSchemaError $S 'PSD507' "the Pattern of $($rule.Name) isn't a valid regex: $($_.Exception.InnerException.Message)" (& $sub 'Pattern') }
    }
    foreach ($mm in 'Min', 'Max') {
        if ($Value.Contains($mm)) {
            $x = $Value[$mm]
            if (-not (Test-PsdNumber $x)) { Add-PsdSchemaError $S 'PSD500' "$mm in $($rule.Name) has to be a number." (& $sub $mm) }
            else { $rule[$mm] = $x }
        }
    }
    if ($null -ne $rule.Min -and $null -ne $rule.Max -and $rule.Min -gt $rule.Max) {
        Add-PsdSchemaError $S 'PSD510' "Min ($($rule.Min)) is bigger than Max ($($rule.Max)) in $($rule.Name), so nothing can fit." (& $sub 'Min')
    }
    if ($Value.Contains('Properties')) {
        $p = $Value['Properties']
        if ($p -isnot [System.Collections.IDictionary]) { Add-PsdSchemaError $S 'PSD500' "Properties in $($rule.Name) has to be a map of keys and their rules." (& $sub 'Properties') }
        else {
            $rule.Properties = [ordered]@{}
            foreach ($k in $p.PSBase.Keys) { $rule.Properties[$k] = New-PsdRule $p[$k] (Join-PsdList (& $sub 'Properties') $k) $S $false }
        }
    }
    if ($Value.Contains('Items')) { $rule.Items = New-PsdRule $Value['Items'] (& $sub 'Items') $S $false }
    if ($Value.Contains('Merge')) {
        # the default operator of the key, used when the data writes it without one
        $x = $Value['Merge']
        $listOk = $rule.Types.Count -eq 0
        foreach ($spec in $rule.Types) { if ($spec.List -or $spec.Name -in 'array', 'any') { $listOk = $true } }
        if ($x -notin $script:PsdDefaultOperators) {
            Add-PsdSchemaError $S 'PSD500' "Merge in $($rule.Name) has to be one of $($script:PsdDefaultOperators -join ', '), but it's $(Format-PsdValueShort $x)." (& $sub 'Merge') @('+=, =+ and |= add to a list, := replaces a map instead of merging it.')
        }
        elseif ($x -ne ':=' -and -not $listOk) {
            Add-PsdSchemaError $S 'PSD500' "Merge = '$x' in $($rule.Name) only works on lists, but its Type isn't one." (& $sub 'Merge') @("Give it a list type like 'string[]' or 'array'.")
        }
        else { $rule.Merge = [string]$x }
    }
    if ($Value.Contains('Default')) {
        $rule.HasDefault = $true
        $rule.Default = $Value['Default']
        $tctx = New-PsdContext -Limits $S.Ctx.Limits
        Test-PsdValueRule $rule.Default $null $rule $rule.Name $tctx $null
        if ($tctx.Errors.Count -gt 0) {
            Add-PsdSchemaError $S 'PSD508' "the Default of $($rule.Name) doesn't fit its own rules: $($tctx.Errors[0].Message)" (& $sub 'Default')
        }
    }
    $rule
}

# --- Validation -------------------------------------------------------------------

function Test-PsdTypeSpec {
    param($Value, $Spec)
    if ($Spec.List) {
        if (-not (Test-PsdList $Value)) { return $false }
        $item = $Spec.Clone()
        $item.List = $false
        foreach ($x in $Value) { if (-not (Test-PsdTypeSpec $x $item)) { return $false } }
        return $true
    }
    switch ($Spec.Kind) {
        'enum' {
            if ($Value -is [enum]) { $Value = $Value.ToString() }
            if ($Value -isnot [string]) { return $false }
            foreach ($m in $Spec.Members) { if ($m -ieq $Value) { return $true } }
            return $false
        }
        'conv' {
            switch ($Spec.Name) {
                'version' { if ($Value -is [version]) { return $true }; $o = $null; return ($Value -is [string] -and [version]::TryParse($Value, [ref]$o)) }
                'guid' { if ($Value -is [guid]) { return $true }; $o = [guid]::Empty; return ($Value -is [string] -and [guid]::TryParse($Value, [ref]$o)) }
                'datetime' {
                    if ($Value -is [datetime]) { return $true }
                    $o = [datetime]::MinValue
                    return ($Value -is [string] -and [datetime]::TryParse($Value, $script:PsdInvariant, [System.Globalization.DateTimeStyles]::None, [ref]$o))
                }
            }
        }
    }
    switch ($Spec.Name) {
        'string' { return ($Value -is [string]) }
        'int' { return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [uint16] -or $Value -is [uint32]) }
        'double' { return (Test-PsdNumber $Value) }
        'bool' { return ($Value -is [bool]) }
        'map' { return ($Value -is [System.Collections.IDictionary]) }
        'array' { return (Test-PsdList $Value) }
        'any' { return $true }
        'null' { return ($null -eq $Value) }
    }
    $false
}

function Get-PsdTypeSpecText {
    param($Spec)
    if ($Spec.List) { return "a list of $($Spec.Text.Substring(0, $Spec.Text.Length - 2))" }
    if ($Spec.Kind -eq 'enum') { return "one of $($Spec.Members -join ', ')" }
    if ($Spec.Kind -eq 'conv') { return "a $($Spec.Name)" }
    @{ string = 'text'; int = 'a whole number'; double = 'a number'; bool = '$true or $false'; map = 'a map'; array = 'a list'; any = 'anything'; null = '$null' }[$Spec.Name]
}

function Get-PsdRuleHint {
    param($Rule)
    if ($Rule.Description) { return @("About this key: $($Rule.Description)") }
    @()
}

function Add-PsdValueError {
    param($Ctx, [string] $Code, [string] $Message, $Node, [string[]] $Hint = @(), [switch] $AtKey)
    if ($null -eq $Node) { Add-PsdError $Ctx $Code $Message -Hint $Hint; return }
    if ($AtKey -and $Node.KeyLine -gt 0) {
        Add-PsdError $Ctx $Code $Message -File $Node.File -Line $Node.KeyLine -Column $Node.KeyCol -Length $Node.KeyLen -Key $Node.Path -Hint $Hint
        return
    }
    Add-PsdNodeError $Ctx $Code $Message $Node -Hint $Hint
}

function Get-PsdChildNode {
    param($Node, $Key)
    if ($null -eq $Node) { return $null }
    if ($Key -is [int]) {
        if ($Node.K -eq 'L' -and $Key -lt $Node.V.Count) { return $Node.V[$Key] }
        return $Node
    }
    if ($Node.K -eq 'M' -and $Node.V.Contains($Key)) { return $Node.V[$Key] }
    $Node
}

function Test-PsdValueRule {
    param($Value, $Node, $Rule, [string] $Path, $Ctx, $Doc, [switch] $NoRequired)
    $shown = $Path
    if (-not $shown) { $shown = 'The file' }
    $hint = Get-PsdRuleHint $Rule

    if ($Rule.Types.Count -gt 0) {
        $ok = $false
        foreach ($spec in $Rule.Types) { if (Test-PsdTypeSpec $Value $spec) { $ok = $true; break } }
        if (-not $ok) {
            $one = $Rule.Types[0]
            if ($Rule.Types.Count -eq 1 -and $one.Kind -eq 'enum' -and -not $one.List -and $Value -is [string]) {
                Add-PsdValueError $Ctx 'PSD504' "$shown can't be '$Value'." $Node (@("Allowed values: $($one.Members -join ', ')") + $hint)
                return
            }
            $want = @($Rule.Types | ForEach-Object { Get-PsdTypeSpecText $_ }) -join ' or '
            Add-PsdValueError $Ctx 'PSD501' "$shown has to be $want, but it's $(Format-PsdValueShort $Value)." $Node $hint
            return
        }
    }
    if ($null -ne $Rule.Enum) {
        if (-not (Test-PsdListHas $Rule.Enum $Value)) {
            $vals = @($Rule.Enum | ForEach-Object { Format-PsdScalarText $_ }) -join ', '
            Add-PsdValueError $Ctx 'PSD504' "$shown can't be $(Format-PsdValueShort $Value)." $Node (@("Allowed values: $vals") + $hint)
            return
        }
    }
    if ($Rule.Regex -and $Value -is [string]) {
        $matched = $true
        try { $matched = $Rule.Regex.IsMatch($Value) }
        catch {
            Add-PsdLimitError $Ctx 'RegexTimeout' "by the Pattern of $shown"
            return
        }
        if (-not $matched) {
            Add-PsdValueError $Ctx 'PSD505' "$shown is '$Value', but it has to match $($Rule.Pattern)." $Node $hint
        }
    }
    if ($null -ne $Rule.Min -or $null -ne $Rule.Max) {
        $size = $null; $what = $null
        if (Test-PsdNumber $Value) { $size = $Value }
        elseif ($Value -is [string]) { $size = $Value.Length; $what = 'characters long' }
        elseif (Test-PsdList $Value) { $size = $Value.Count; $what = 'items' }
        if ($null -ne $size) {
            $low = ($null -ne $Rule.Min -and $size -lt $Rule.Min)
            $high = ($null -ne $Rule.Max -and $size -gt $Rule.Max)
            if ($low -or $high) {
                $range = if ($null -ne $Rule.Min -and $null -ne $Rule.Max) { "between $($Rule.Min) and $($Rule.Max)" } elseif ($null -ne $Rule.Min) { "at least $($Rule.Min)" } else { "at most $($Rule.Max)" }
                if ($what) { $msg = "$shown is $size $what, but it has to be $range." } else { $msg = "$shown is $size, but it has to be $range." }
                Add-PsdValueError $Ctx 'PSD506' $msg $Node $hint
            }
        }
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $props = $Rule.Properties
        foreach ($k in @($Value.PSBase.Keys)) {
            $child = Get-PsdChildNode $Node ([string]$k)
            $cp = Join-PsdPath $Path ([string]$k)
            if ($props -and $props.Contains($k)) { Test-PsdValueRule $Value[$k] $child $props[$k] $cp $Ctx $Doc -NoRequired:$NoRequired }
            elseif ($Rule.Items) { Test-PsdValueRule $Value[$k] $child $Rule.Items $cp $Ctx $Doc -NoRequired:$NoRequired }
            elseif ($props -and -not $Rule.AllowUnknown) {
                $where = if ($Path) { "$Path doesn't have a key called '$k' in the schema." } else { "the schema doesn't have a key called '$k'." }
                Add-PsdValueError $Ctx 'PSD503' $where $child @((Get-PsdDidYouMean ([string]$k) $props.PSBase.Keys)) -AtKey
            }
        }
        if ($props -and -not $NoRequired) {
            foreach ($k in $props.PSBase.Keys) {
                if ($props[$k].Required -and -not $Value.Contains($k)) {
                    $cp = Join-PsdPath $Path $k
                    $files = New-PsdList
                    $file = $null
                    if ($Doc) {
                        $file = $Doc.Entry
                        for ($i = $Doc.Layers.Count - 1; $i -ge 0; $i--) { $f = $Doc.Layers[$i].File; if (-not $f.Synthetic -or $f.Named) { $files.Add($f.Name + $f.Ext) } }
                    }
                    $extra = @()
                    if ($files.Count -gt 0) { $extra = @("Looked in: $($files -join ', ')") }
                    Add-PsdError $Ctx 'PSD502' "$cp is required, but none of these files set it." -File $file -Key $cp -Hint ($extra + (Get-PsdRuleHint $props[$k]))
                }
            }
        }
    }
    elseif ((Test-PsdList $Value) -and $Rule.Items) {
        for ($i = 0; $i -lt $Value.Count; $i++) {
            Test-PsdValueRule $Value[$i] (Get-PsdChildNode $Node $i) $Rule.Items (Join-PsdPath $Path $i) $Ctx $Doc -NoRequired:$NoRequired
        }
    }
}

# --- Defaults and inference -----------------------------------------------------------

function Add-PsdDefaultValues {
    param($Value, $Rule)
    if ($Value -is [System.Collections.IDictionary] -and $Rule.Properties) {
        foreach ($k in $Rule.Properties.PSBase.Keys) {
            $r = $Rule.Properties[$k]
            if (-not $Value.Contains($k)) {
                if ($r.HasDefault) { $Value[$k] = ConvertTo-PsdOutput (Copy-PsdPlain $r.Default) }
            }
            else { Add-PsdDefaultValues $Value[$k] $r }
        }
    }
    if ((Test-PsdList $Value) -and $Rule.Items) { foreach ($x in $Value) { Add-PsdDefaultValues $x $Rule.Items } }
}

function Copy-PsdPlain {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}; foreach ($k in $Value.PSBase.Keys) { $o[$k] = Copy-PsdPlain $Value[$k] }; return , $o
    }
    if (Test-PsdList $Value) { $l = New-PsdList; foreach ($x in $Value) { $l.Add((Copy-PsdPlain $x)) }; return , $l }
    , $Value
}

function Get-PsdInferredType {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [bool]) { return 'bool' }
    if ($Value -is [int] -or $Value -is [long]) { return 'int' }
    if (Test-PsdNumber $Value) { return 'double' }
    if ($Value -is [System.Collections.IDictionary]) { return 'map' }
    if (Test-PsdList $Value) { return 'array' }
    'any'
}

function New-PsdInferredRule {
    param($Value)
    $t = Get-PsdInferredType $Value
    if ($t -eq 'map') {
        $props = [ordered]@{}
        foreach ($k in $Value.PSBase.Keys) { $props[$k] = New-PsdInferredRule $Value[$k] }
        return [ordered]@{ Type = 'map'; Properties = $props }
    }
    if ($t -eq 'array') {
        $types = New-PsdList
        foreach ($x in $Value) { $it = Get-PsdInferredType $x; if (-not $types.Contains($it)) { $types.Add($it) } }
        if ($types.Count -eq 1 -and $types[0] -in 'string', 'int', 'double', 'bool') { return "$($types[0])[]" }
        if ($types.Count -eq 1 -and $types[0] -eq 'map') {
            $merged = [ordered]@{}
            foreach ($x in $Value) { foreach ($k in $x.PSBase.Keys) { if (-not $merged.Contains($k)) { $merged[$k] = $x[$k] } } }
            return [ordered]@{ Type = 'array'; Items = (New-PsdInferredRule $merged) }
        }
        return 'array'
    }
    $t
}
