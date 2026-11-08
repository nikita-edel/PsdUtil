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
    An object from a generated class works too, if it was made from a map.

    .PARAMETER Include
    Maps from the caller, by name. They work like '!include': read them with !<name::Key>.
    Their keys aren't in the result and the schema doesn't check them.

    .PARAMETER Loader
    Reads files that aren't .psd1, like .ps1 scripts that return a map or a generated class: a script
    block that gets the full path and returns the map, for example { param($Path) & $Path }. PsdUtil
    itself runs no code; without -Loader a .ps1 is error PSD108. What the loader returns is the file:
    '!merge', '!include', '!name' and '!schema' work in it, with paths relative to its folder.

    .PARAMETER Merge
    Default operators for keys written without one, by key path, for example @{ '**' = '+=' } (every list
    adds to the one below, like 'Key +=') or @{ Tags = '+='; 'Server.*' = '|=' }. * is one key, ** any
    number of keys. Operators: +=, =+, |= for lists, := to replace a map instead of merging it. An
    operator is used only where it fits the value; one written in the data wins. The first pattern that
    matches wins, then Merge in the schema. Use [ordered]@{ } when the order matters.

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

    .EXAMPLE
    Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'prod' } }

    .EXAMPLE
    Import-Psd ./app.psd1 -Merge @{ '**' = '+=' }

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

        [object] $Override,

        [System.Collections.IDictionary] $Include,

        [System.Collections.IDictionary] $Merge,

        [scriptblock] $Loader,

        [ValidateSet('Error', 'Warn', 'Null', 'Keep')]
        [string] $UnresolvedReference = 'Error',

        [System.Collections.IDictionary] $Limits
    )
    process {
        $r = Invoke-PsdLoad -Path $Path -Schema $Schema -Override $Override -Include $Include -Merge $Merge -Loader $Loader -Unresolved $UnresolvedReference -Limits $Limits
        Write-PsdResult $PSCmdlet $r.Ctx ([IO.Path]::GetFileName($Path))
        if ($r.Ctx.Errors.Count -eq 0) { $r.Value }
    }
}
