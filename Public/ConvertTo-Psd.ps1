function ConvertTo-Psd {
    <#
    .SYNOPSIS
    Turns an object into .psd1 text.

    .DESCRIPTION
    Maps, ordered maps, PSCustomObjects and class instances become @{ }, lists become @( ).
    Dates are written as ISO-8601 text, Guid, Version and Uri as text, enums by name.
    Other objects become a map of their public properties. Script blocks and secure strings
    can't be written. Text containing !< is escaped as !!<, so the file reads back the same.
    An object from a generated class that was made from a map is written as that map, exactly as
    it was given, so '!if', merge operators and references stay.

    .PARAMETER Format
    A map of format options. Defaults:
    @{ Indent = 4; Quote = 'Single'; SortKeys = $false; AlignEquals = $false; InlineArrayMax = 4; LineEnding = 'Auto'; Bom = $false }

    .PARAMETER Depth
    How deep objects are followed. Defaults to 64.

    .EXAMPLE
    @{ Name = 'app'; Ports = 80, 443 } | ConvertTo-Psd
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object] $InputObject,

        [System.Collections.IDictionary] $Format,

        [ValidateRange(1, 1000)]
        [int] $Depth = 64
    )
    begin { $items = New-PsdList; $fromPipe = -not $PSBoundParameters.ContainsKey('InputObject') }
    process { $items.Add($InputObject) }
    end {
        $value = $InputObject
        if ($fromPipe) { if ($items.Count -eq 1) { $value = $items[0] } else { $value = $items.ToArray() } }
        $ctx = New-PsdContext
        $f = Get-PsdFormat $Format $ctx
        $text = $null
        if ($ctx.Errors.Count -eq 0) { $text = ConvertTo-PsdTextInternal $value $f $Depth $ctx }
        Write-PsdResult $PSCmdlet $ctx $null
        if ($ctx.Errors.Count -eq 0) { $text }
    }
}
