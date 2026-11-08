function New-PsdType {
    <#
    .SYNOPSIS
    Writes classes and enums from a schema, for autocomplete in config scripts.

    .DESCRIPTION
    Maps with Properties become classes, Enum on text becomes an enum, enums from '!types' are
    copied. Value types are [Nullable[T]], so properties you don't set stay $null.
    Use the file with: using module ./App.Types.psm1

    A class made from a map, like [App]@{ ... }, keeps that map. Keys starting with ! and keys ending
    in a merge operator are allowed in it, and Export-Psd, ConvertTo-Psd, Merge-Psd and -Override use
    it, so the file holds what was written. Any other key that isn't a property throws.

    .PARAMETER Name
    The name of the top-level class. Nested classes are named after it: App, AppServer, ...

    .PARAMETER Constant
    Classes of named values, for values that are known only when the types are written. Each entry is a
    class with one static property per value:
    a list names each value after itself: Region = @('eu-west') gives [Region]::eu_west, which is 'eu-west';
    a map gives the names: Port = @{ Http = 80; Https = 443 } gives [Port]::Http, which is 80.
    Values can be text, numbers, $true, $false, $null, lists and maps; the property is typed by the value
    ([string], [int], [bool], [object[]], [hashtable], ...). A character that can't be in a name becomes _,
    a name that starts with a digit gets _ in front. The schema doesn't check these values.

    .EXAMPLE
    New-PsdType -Schema ./app.schema.psd1 -Path ./App.Types.psm1 -Name App

    .EXAMPLE
    New-PsdType -Schema ./app.schema.psd1 -Path ./App.Types.psm1 -Name App -Constant @{ Region = @('eu-west', 'us-east'); Port = @{ Http = 80; Https = 443 } }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Schema,

        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name,

        [System.Collections.IDictionary] $Constant
    )
    $ctx = New-PsdContext
    $rules = Import-PsdSchemaRules (Resolve-PsdUserPath $Schema) $ctx $null
    $text = $null
    if ($rules) {
        $command = "New-PsdType -Schema $Schema"
        if ($Path) { $command += " -Path $Path" }
        $command += " -Name $Name"
        if ($Constant) { $command += " -Constant @{ $(@($Constant.PSBase.Keys) -join '; ') }" }
        $outDir = (Get-Location -PSProvider FileSystem).ProviderPath
        if ($Path) { $outDir = [IO.Path]::GetDirectoryName((Resolve-PsdUserPath $Path)) }
        $text = New-PsdTypeText $rules $Name $command $outDir $ctx $Constant
    }
    if ($ctx.Errors.Count -eq 0 -and $Path) {
        $full = Resolve-PsdUserPath $Path
        if ($PSCmdlet.ShouldProcess($full, 'Write types')) { $null = Write-PsdTextFile $full $text $false $ctx }
    }
    Write-PsdResult $PSCmdlet $ctx $null
    if ($ctx.Errors.Count -eq 0 -and -not $Path) { $text }
}
