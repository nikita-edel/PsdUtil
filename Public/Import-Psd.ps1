function Import-Psd {
    <#
    .SYNOPSIS
    Loads a .psd1 file with references, merging, includes, conditions and an optional schema.

    .DESCRIPTION
    Reads the file without running any code, follows '!merge' and '!include', decides every '!if',
    works out every '!<...>' reference and checks the result against a schema when one is given
    with -Schema or '!schema' in the file.

    All problems are reported together. If there is any, nothing is returned.

    .PARAMETER Path
    The file to load.

    .PARAMETER Schema
    A schema file. Wins over '!schema' in the file.

    .PARAMETER Override
    A map applied as one more layer on top of the file, for example @{ Stage = 'prod' }.

    .PARAMETER UnresolvedReference
    What happens when a reference points to a key that doesn't exist.
    Error (default), Warn (a warning, the value becomes $null), Null (silently $null),
    Keep (the reference text stays as it is written).

    .PARAMETER Limits
    Changes the limits, for example @{ MaxDepth = 128 }.
    Limits: MaxDepth, MaxFiles, MaxFileSize, MaxStringLength, MaxNodes, RegexTimeout (seconds).

    .EXAMPLE
    $config = Import-Psd ./app.psd1

    .EXAMPLE
    Import-Psd ./app.psd1 -Override @{ Stage = 'prod' } -Schema ./app.schema.psd1

    .OUTPUTS
    An ordered dictionary.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [string] $Schema,

        [System.Collections.IDictionary] $Override,

        [ValidateSet('Error', 'Warn', 'Null', 'Keep')]
        [string] $UnresolvedReference = 'Error',

        [System.Collections.IDictionary] $Limits
    )
    process {
        $r = Invoke-PsdLoad -Path $Path -Schema $Schema -Override $Override -Unresolved $UnresolvedReference -Limits $Limits
        Write-PsdResult $PSCmdlet $r.Ctx ([IO.Path]::GetFileName($Path))
        if ($r.Ctx.Errors.Count -eq 0) { $r.Value }
    }
}
