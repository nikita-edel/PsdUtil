function Test-Psd {
    <#
    .SYNOPSIS
    Checks whether a file loads without problems: syntax, references and schema.

    .PARAMETER Raw
    Also checks each file of the chain on its own against the schema (without Required).

    .EXAMPLE
    Test-Psd ./app.psd1 -Schema ./app.schema.psd1
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [string] $Schema,

        [object] $Override,

        [switch] $Raw,

        [System.Collections.IDictionary] $Limits
    )
    process {
        $r = Invoke-PsdLoad -Path $Path -Schema $Schema -Override $Override -Raw:$Raw -Limits $Limits
        $r.Ctx.Errors.Count -eq 0
    }
}
