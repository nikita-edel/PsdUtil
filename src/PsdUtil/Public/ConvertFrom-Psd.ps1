function ConvertFrom-Psd {
    <#
    .SYNOPSIS
    Loads .psd1 text, with the same features as Import-Psd.

    .PARAMETER Text
    The text of a data file.

    .PARAMETER BasePath
    The folder that relative paths in '!merge', '!include' and '!schema' start from.
    Defaults to the current folder.

    .PARAMETER Name
    The name the text gets, for !<@name> and error messages. Defaults to 'input'.

    .PARAMETER Include
    Maps from the caller, by name. They work like '!include': read them with !<name::Key>.
    Their keys aren't in the result and the schema doesn't check them.

    .PARAMETER Merge
    Default operators for keys written without one, by key path, for example @{ '**' = '+=' } (every list
    adds to the one below, like 'Key +=') or @{ Tags = '+='; 'Server.*' = '|=' }. * is one key, ** any
    number of keys. Operators: +=, =+, |= for lists, := to replace a map instead of merging it. An
    operator is used only where it fits the value; one written in the data wins. The first pattern that
    matches wins, then Merge in the schema. Use [ordered]@{ } when the order matters.

    .EXAMPLE
    ConvertFrom-Psd -Text "@{ A = 1; B = '!<A>' }"
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Text,

        [string] $BasePath,

        [string] $Name = 'input',

        [string] $Schema,

        [object] $Override,

        [System.Collections.IDictionary] $Include,

        [System.Collections.IDictionary] $Merge,

        [ValidateSet('Error', 'Warn', 'Null', 'Keep')]
        [string] $UnresolvedReference = 'Error',

        [System.Collections.IDictionary] $Limits
    )
    process {
        $r = Invoke-PsdLoad -Text $Text -BasePath $BasePath -Name $Name -Schema $Schema -Override $Override -Include $Include -Merge $Merge -Unresolved $UnresolvedReference -Limits $Limits
        Write-PsdResult $PSCmdlet $r.Ctx "$Name.psd1"
        if ($r.Ctx.Errors.Count -eq 0) { $r.Value }
    }
}
