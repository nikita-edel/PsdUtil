function Add-PsdDefault {
    <#
    .SYNOPSIS
    Fills in the schema's Default values for keys that are missing. Changes the object in place.

    .EXAMPLE
    Add-PsdDefault $config -Schema ./app.schema.psd1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Collections.IDictionary] $InputObject,

        [Parameter(Mandatory)]
        [string] $Schema,

        [switch] $PassThru
    )
    $ctx = New-PsdContext
    $rules = Import-PsdSchemaRules (Resolve-PsdUserPath $Schema) $ctx $null
    if ($rules) { Add-PsdDefaultValues $InputObject $rules }
    Write-PsdResult $PSCmdlet $ctx $null
    if ($PassThru) { $InputObject }
}

function New-PsdSchema {
    <#
    .SYNOPSIS
    Makes a starting schema from a sample file or object.

    .DESCRIPTION
    Every key gets the type it has in the sample. Lists of one type become 'string[]' and so on,
    lists of maps get an Items rule. Add Required, Enum, Min, Max and Description yourself.

    .EXAMPLE
    New-PsdSchema -FromFile ./result.psd1 -Path ./starter.schema.psd1
    #>
    [CmdletBinding(DefaultParameterSetName = 'File', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'File')]
        [string] $FromFile,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [System.Collections.IDictionary] $InputObject,

        [string] $Path
    )
    $value = $InputObject
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $r = Invoke-PsdLoad -Path $FromFile
        if ($r.Ctx.Errors.Count -gt 0) { Write-PsdResult $PSCmdlet $r.Ctx $FromFile; return }
        $value = $r.Value
    }
    $rule = New-PsdInferredRule $value
    $schema = [ordered]@{ Properties = $rule.Properties }
    if (-not $Path) { return $schema }
    if ($PSCmdlet.ShouldProcess($Path, 'Write schema')) { Export-Psd $schema -Path $Path }
}

function New-PsdType {
    <#
    .SYNOPSIS
    Writes classes and enums from a schema, for autocomplete in config scripts.

    .DESCRIPTION
    Maps with Properties become classes, Enum on text becomes an enum, enums from '!types' are
    copied. Value types are [Nullable[T]], so properties you don't set stay $null.
    Use the file with: using module ./App.Types.psm1

    .PARAMETER Name
    The name of the top-level class. Nested classes are named after it: App, AppServer, ...

    .EXAMPLE
    New-PsdType -Schema ./app.schema.psd1 -Path ./App.Types.psm1 -Name App
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Schema,

        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )
    $ctx = New-PsdContext
    $rules = Import-PsdSchemaRules (Resolve-PsdUserPath $Schema) $ctx $null
    $text = $null
    if ($rules) {
        $command = "New-PsdType -Schema $Schema"
        if ($Path) { $command += " -Path $Path" }
        $command += " -Name $Name"
        $outDir = (Get-Location -PSProvider FileSystem).ProviderPath
        if ($Path) { $outDir = [IO.Path]::GetDirectoryName((Resolve-PsdUserPath $Path)) }
        $text = New-PsdTypeText $rules $Name $command $outDir $ctx
    }
    if ($ctx.Errors.Count -eq 0 -and $Path) {
        $full = Resolve-PsdUserPath $Path
        if ($PSCmdlet.ShouldProcess($full, 'Write types')) { $null = Write-PsdTextFile $full $text $false $ctx }
    }
    Write-PsdResult $PSCmdlet $ctx $null
    if ($ctx.Errors.Count -eq 0 -and -not $Path) { $text }
}
