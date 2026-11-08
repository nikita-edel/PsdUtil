# Classes and enums from a schema, for autocomplete in config scripts.

$script:PsdRxIdent = New-Object regex '^[A-Za-z_][A-Za-z0-9_]*$'

function ConvertTo-PsdPascal {
    param([string] $Text)
    $out = ''
    foreach ($p in [regex]::Split($Text, '[^A-Za-z0-9]+')) {
        if ($p.Length -eq 0) { continue }
        $out += $p.Substring(0, 1).ToUpperInvariant() + $p.Substring(1)
    }
    $out
}

function Get-PsdRelativePath {
    param([string] $FromDir, [string] $ToFile)
    $from = New-Object System.Uri ($FromDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
    $to = New-Object System.Uri $ToFile
    $rel = [Uri]::UnescapeDataString($from.MakeRelativeUri($to).ToString()).Replace('\', '/')
    if (-not $rel.StartsWith('../')) { $rel = './' + $rel }
    $rel
}

function Get-PsdTypeName {
    param($G, [string] $Path)
    $name = $G.Name + (ConvertTo-PsdPascal $Path)
    if (-not $script:PsdRxIdent.IsMatch($name)) {
        Add-PsdError $G.Ctx 'PSD512' "$Path would become the class name '$name', which isn't valid." -Hint @('Use -Name with a name that starts with a letter.')
        return $null
    }
    if ($G.Names.ContainsKey($name)) {
        Add-PsdError $G.Ctx 'PSD512' "$Path and $($G.Names[$name]) would both become the class name '$name'." -Hint @('Rename one of the keys.')
        return $null
    }
    $G.Names[$name] = $Path
    $name
}

function Format-PsdPropName {
    param($G, [string] $Key, [string] $Path)
    if ($script:PsdRxIdent.IsMatch($Key)) { return '$' + $Key }
    if ($Key.IndexOf('}') -ge 0 -or $Key.IndexOf('`') -ge 0) {
        Add-PsdError $G.Ctx 'PSD512' "the key '$Key' at $Path can't be a property name, because it contains } or a backtick."
        return $null
    }
    '${' + $Key + '}'
}

function Add-PsdTypeEnum {
    param($G, $Spec)
    if ($G.Enums.Contains($Spec.Name)) { return }
    $rel = Get-PsdRelativePath $G.OutDir $Spec.Source
    $G.Enums[$Spec.Name] = "$($Spec.Def)  # copied from $rel"
}

function Get-PsdTypeExpr {
    param($G, $Rule, [string] $Path, [string] $Key, [string] $Owner)
    $specs = New-PsdList
    foreach ($s in $Rule.Types) { if ($s.Name -ne 'null' -or $s.Kind -ne 'base') { $specs.Add($s) } }
    if ($specs.Count -eq 0) { return 'object' }
    if ($specs.Count -gt 1) {
        foreach ($s in $specs) {
            if ($s.Kind -eq 'base' -and $s.Name -eq 'map' -and -not $s.List -and $Rule.Properties) {
                $names = @($specs | ForEach-Object { "'" + $_.Text + "'" }) -join ' or '
                $G.Comments = @("# $Key allows $names, so $Owner.$Key is [object].", '# Cast to this class to get completion for the map form.')
                $cn = Add-PsdTypeClass $G $Rule $Path
                if ($null -eq $cn) { return 'object' }
            }
        }
        return 'object'
    }
    $spec = $specs[0]
    if ($spec.List) {
        $item = @{}
        foreach ($k in $spec.PSBase.Keys) { $item[$k] = $spec[$k] }
        $item.List = $false
        $itemRule = @{ Types = (New-PsdList); Enum = $null; Properties = $null; Items = $null }
        $itemRule.Types.Add($item)
        $t = Get-PsdTypeExpr $G $itemRule $Path $Key $Owner
        return ($t -replace '^Nullable\[(.+)\]$', '$1') + '[]'
    }
    switch ($spec.Kind) {
        'enum' {
            if ($spec.Source) { Add-PsdTypeEnum $G $spec; return "Nullable[$($spec.Name)]" }
            return "Nullable[$($spec.DotNet)]"
        }
        'conv' {
            switch ($spec.Name) { 'version' { return 'version' } 'guid' { return 'Nullable[guid]' } 'datetime' { return 'Nullable[datetime]' } }
        }
    }
    switch ($spec.Name) {
        'string' {
            if ($Rule.Enum -and $Rule.Enum.Count -gt 0) {
                $ok = $true
                foreach ($x in $Rule.Enum) { if ($x -isnot [string] -or -not $script:PsdRxIdent.IsMatch($x)) { $ok = $false } }
                if ($ok) {
                    $en = Get-PsdTypeName $G $Path
                    if ($null -eq $en) { return 'string' }
                    $G.Enums[$en] = "enum $en { $($Rule.Enum -join '; ') }"
                    return "Nullable[$en]"
                }
            }
            return 'string'
        }
        'int' { return 'Nullable[int]' }
        'double' { return 'Nullable[double]' }
        'bool' { return 'Nullable[bool]' }
        'map' {
            if ($Rule.Properties) {
                $cn = Add-PsdTypeClass $G $Rule $Path
                if ($cn) { return $cn }
                return 'hashtable'
            }
            return 'hashtable'
        }
        'array' {
            if ($Rule.Items) {
                $t = Get-PsdTypeExpr $G $Rule.Items "$Path.Item" $Key $Owner
                return ($t -replace '^Nullable\[(.+)\]$', '$1') + '[]'
            }
            return 'object[]'
        }
    }
    'object'
}

function Add-PsdTypeClass {
    param($G, $Rule, [string] $Path)
    $comments = $G.Comments
    $G.Comments = $null
    $name = if ($Path) { Get-PsdTypeName $G $Path } else { $G.Name }
    if ($null -eq $name) { return $null }
    if (-not $Path) { $G.Names[$name] = '(top)' }
    $lines = New-PsdList
    $lines.Add('    hidden [System.Collections.IDictionary] $__PsdMap')
    if ($Rule.Properties) {
        foreach ($k in $Rule.Properties.PSBase.Keys) {
            $childPath = if ($Path) { "$Path.$k" } else { $k }
            $t = Get-PsdTypeExpr $G $Rule.Properties[$k] $childPath $k $name
            $pn = Format-PsdPropName $G $k $childPath
            if ($null -eq $pn) { continue }
            $lines.Add("    [$t] $pn")
        }
    }
    $lines.Add('')
    $lines.Add("    $name() { }")
    $lines.Add("    $name([System.Collections.IDictionary] `$map) { [$($G.Helper)]::Apply(`$this, `$map) }")
    $text = ''
    if ($comments) { $text = ($comments -join "`n") + "`n" }
    $text += "class $name {`n" + ($lines -join "`n") + "`n}"
    $G.Classes.Add($text)
    $name
}

# Lets a cast keep what a data file can hold: '!if', merge operators and references.
function Get-PsdTypeHelperText {
    param([string] $Helper)
    @(
        "class $Helper {"
        '    static [void] Apply([object] $target, [System.Collections.IDictionary] $map) {'
        '        $target.__PsdMap = $map'
        '        foreach ($key in $map.PSBase.Keys) {'
        '            $name = [string]$key'
        '            if ($name.StartsWith(''!'') -or $name -match '' (\+=|=\+|\|=|-=|:=)$'') { continue }'
        '            $prop = $target.GetType().GetProperty($name, [System.Reflection.BindingFlags]''Public, Instance, IgnoreCase'')'
        '            if ($null -eq $prop) { throw "$($target.GetType().Name) has no key ''$name''." }'
        '            $value = $map[$key]'
        '            if ($value -is [string] -and $value.Contains(''!<'') -and $prop.PropertyType -ne [string]) { continue }'
        '            $target.$name = $value'
        '        }'
        '    }'
        '}'
    ) -join "`n"
}

# A value as a static property name: a character that can't be in a name becomes _, a leading digit gets _,
# and so do names PowerShell has as variables already: true, false, null, this.
function ConvertTo-PsdConstantName {
    param([string] $Value)
    $n = [regex]::Replace($Value, '[^A-Za-z0-9_]', '_')
    if ($n -match '^[0-9]' -or $n -in 'true', 'false', 'null', 'this') { $n = '_' + $n }
    $n
}

# The type of a static property for a -Constant value.
function Get-PsdConstantType {
    param($Value)
    if ($null -eq $Value) { return 'object' }
    if ($Value -is [bool]) { return 'bool' }
    if ($Value -is [int] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [uint16]) { return 'int' }
    if ($Value -is [long] -or $Value -is [uint32]) { return 'long' }
    if ($Value -is [double] -or $Value -is [single]) { return 'double' }
    if ($Value -is [decimal] -or $Value -is [uint64]) { return 'decimal' }
    if (Test-PsdList $Value) { return 'object[]' }
    # text, and what the writer writes as text: dates, versions, guids, enums
    if (Test-PsdScalarOut $Value) { return 'string' }
    # maps and objects are written as @{ }
    'hashtable'
}

# Classes of named values from -Constant, one static property each. A list names each value after itself:
# Region = @('eu-west') gives [Region]::eu_west. A map gives the names: Port = @{ Http = 80 } gives [Port]::Http.
# Values are written as ConvertTo-Psd writes them, exactly as given, and typed by their kind.
function Add-PsdConstantClass {
    param($G, $Constant)
    $S = @{ Ctx = $G.Ctx; Format = (Get-PsdFormat $null $G.Ctx); Depth = 64; Stack = (New-PsdList); Path = ''; NL = "`n"; Raw = $true }
    foreach ($class in @($Constant.PSBase.Keys)) {
        $className = [string]$class
        if (-not $script:PsdRxIdent.IsMatch($className)) {
            Add-PsdError $G.Ctx 'PSD512' "-Constant: '$className' isn't a valid class name." -Hint @('Use a name that starts with a letter and has only letters, digits and _.')
            continue
        }
        if ($className -ieq $G.Name -or $G.Names.ContainsKey($className)) {
            Add-PsdError $G.Ctx 'PSD512' "-Constant: the class name '$className' is already used." -Hint @('Rename the -Constant entry.')
            continue
        }
        $G.Names[$className] = "-Constant $className"
        # name as written -> value
        $entries = New-PsdList
        $given = $Constant[$class]
        if ($given -is [System.Collections.IDictionary]) {
            foreach ($k in @($given.PSBase.Keys)) { $entries.Add(@{ Name = [string]$k; Value = $given[$k] }) }
        }
        else {
            foreach ($value in (Get-PsdItems $given)) {
                if ($null -eq $value -or (Test-PsdContainer $value)) {
                    Add-PsdError $G.Ctx 'PSD512' "-Constant ${className}: a list names each value after itself, so its values can't be $(Get-PsdKindText $value)." -Hint @("To name them yourself, give a map: $className = @{ Name = ... }")
                    continue
                }
                $entries.Add(@{ Name = (Format-PsdScalarText $value); Value = $value })
            }
        }
        $members = [ordered]@{}
        $lines = New-PsdList
        foreach ($entry in $entries) {
            $member = ConvertTo-PsdConstantName $entry.Name
            if ($member -notmatch '[A-Za-z0-9]') {
                Add-PsdError $G.Ctx 'PSD512' "-Constant ${className}: '$($entry.Name)' can't be a property name." -Hint @('A name needs a letter or digit.')
                continue
            }
            $same = $null
            foreach ($k in $members.PSBase.Keys) { if ($k -ieq $member) { $same = $k } }
            if ($null -ne $same) {
                Add-PsdError $G.Ctx 'PSD512' "-Constant ${className}: '$($members[$same])' and '$($entry.Name)' would both become the property '$member'."
                continue
            }
            $members[$member] = $entry.Name
            $S.Path = "$className.$member"
            $text = Write-PsdValueText $entry.Value $S 1
            $lines.Add("    static [$(Get-PsdConstantType $entry.Value)] `$$member = $text")
        }
        $G.Constants.Add("class $className {`n$($lines -join "`n")`n}")
    }
}

function New-PsdTypeText {
    param($Rules, [string] $Name, [string] $Command, [string] $OutDir, $Ctx, $Constant = $null)
    if (-not $script:PsdRxIdent.IsMatch($Name)) {
        Add-PsdError $Ctx 'PSD512' "'$Name' isn't a valid class name." -Hint @('Use a name that starts with a letter and has only letters, digits and _.')
        return $null
    }
    $g = @{ Ctx = $Ctx; Name = $Name; OutDir = $OutDir; Enums = [ordered]@{}; Classes = (New-PsdList); Names = @{}; Comments = $null; Helper = "${Name}PsdMap"; Constants = (New-PsdList) }
    $g.Names[$g.Helper] = '(helper)'
    # first, so a class of the schema with the same name is reported
    if ($null -ne $Constant) { Add-PsdConstantClass $g $Constant }
    $null = Add-PsdTypeClass $g $Rules ''
    foreach ($e in @($g.Enums.PSBase.Keys)) {
        if ($null -ne $Constant -and $Constant.Contains($e)) {
            Add-PsdError $Ctx 'PSD512' "-Constant: the class name '$e' is also an enum of the schema." -Hint @('Rename the -Constant entry.')
        }
    }
    $parts = New-PsdList
    $parts.Add("# Generated by: $Command`n# Do not edit. Run it again after changing the schema.")
    if ($g.Enums.PSBase.Count -gt 0) { $parts.Add((@($g.Enums.PSBase.Values) -join "`n")) }
    foreach ($c in $g.Constants) { $parts.Add($c) }
    $parts.Add((Get-PsdTypeHelperText $g.Helper))
    foreach ($c in $g.Classes) { $parts.Add($c) }
    ($parts -join "`n`n") + "`n"
}
