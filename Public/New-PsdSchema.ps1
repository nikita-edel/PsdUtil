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
