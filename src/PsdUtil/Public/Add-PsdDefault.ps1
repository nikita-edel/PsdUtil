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
