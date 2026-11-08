function Get-PsdError {
    <#
    .SYNOPSIS
    Returns the problems Test-Psd would find, as objects.

    .DESCRIPTION
    Each object has Code, File, Line, Column, Key and Message.
    With -InputObject, checks an object already in memory against -Schema.

    .EXAMPLE
    Get-PsdError ./app.psd1 -Schema ./app.schema.psd1

    .EXAMPLE
    Get-PsdError -InputObject $config -Schema ./app.schema.psd1
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'File', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [object] $InputObject,

        [Parameter(ParameterSetName = 'File')]
        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [string] $Schema,

        [Parameter(ParameterSetName = 'File')]
        [object] $Override,

        [Parameter(ParameterSetName = 'File')]
        [switch] $Raw,

        [System.Collections.IDictionary] $Limits
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $ctx = New-PsdContext -Limits $Limits
            $rules = Import-PsdSchemaRules (Resolve-PsdUserPath $Schema) $ctx $null
            if ($rules) { Test-PsdValueRule (Copy-PsdPlain $InputObject) $null $rules '' $ctx $null }
        }
        else {
            $r = Invoke-PsdLoad -Path $Path -Schema $Schema -Override $Override -Raw:$Raw -Limits $Limits
            $ctx = $r.Ctx
        }
        foreach ($e in $ctx.Errors) { ConvertTo-PsdErrorObject $e }
    }
}
