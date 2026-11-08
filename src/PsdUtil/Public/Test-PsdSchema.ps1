function Test-PsdSchema {
    <#
    .SYNOPSIS
    Checks an object already in memory against a schema. Returns $true or $false.

    .DESCRIPTION
    Use Get-PsdError -InputObject ... -Schema ... to see what's wrong.

    .EXAMPLE
    Test-PsdSchema $config -Schema ./app.schema.psd1
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Schema
    )
    process {
        $ctx = New-PsdContext
        $rules = Import-PsdSchemaRules (Resolve-PsdUserPath $Schema) $ctx $null
        if ($rules) { Test-PsdValueRule (Copy-PsdPlain $InputObject) $null $rules '' $ctx $null }
        $ctx.Errors.Count -eq 0
    }
}
