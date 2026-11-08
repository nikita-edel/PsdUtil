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

        [ValidateSet('Error', 'Warn', 'Null', 'Keep')]
        [string] $UnresolvedReference = 'Error',

        [System.Collections.IDictionary] $Limits
    )
    process {
        $r = Invoke-PsdLoad -Text $Text -BasePath $BasePath -Name $Name -Schema $Schema -Override $Override -Include $Include -Unresolved $UnresolvedReference -Limits $Limits
        Write-PsdResult $PSCmdlet $r.Ctx "$Name.psd1"
        if ($r.Ctx.Errors.Count -eq 0) { $r.Value }
    }
}
