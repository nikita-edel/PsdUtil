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

function New-PsdTypeText {
    param($Rules, [string] $Name, [string] $Command, [string] $OutDir, $Ctx)
    if (-not $script:PsdRxIdent.IsMatch($Name)) {
        Add-PsdError $Ctx 'PSD512' "'$Name' isn't a valid class name." -Hint @('Use a name that starts with a letter and has only letters, digits and _.')
        return $null
    }
    $g = @{ Ctx = $Ctx; Name = $Name; OutDir = $OutDir; Enums = [ordered]@{}; Classes = (New-PsdList); Names = @{}; Comments = $null; Helper = "${Name}PsdMap" }
    $g.Names[$g.Helper] = '(helper)'
    $null = Add-PsdTypeClass $g $Rules ''
    $parts = New-PsdList
    $parts.Add("# Generated by: $Command`n# Do not edit. Run it again after changing the schema.")
    if ($g.Enums.PSBase.Count -gt 0) { $parts.Add((@($g.Enums.PSBase.Values) -join "`n")) }
    $parts.Add((Get-PsdTypeHelperText $g.Helper))
    foreach ($c in $g.Classes) { $parts.Add($c) }
    ($parts -join "`n`n") + "`n"
}
