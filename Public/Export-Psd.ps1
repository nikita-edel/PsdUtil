function Export-Psd {
    <#
    .SYNOPSIS
    Writes an object to a .psd1 file.

    .DESCRIPTION
    Same output as ConvertTo-Psd, including the kept map of a generated class, written as UTF-8. Set Bom = $true in -Format for a byte order mark.
    On Windows PowerShell 5.1, Import-PowerShellDataFile misreads non-ASCII characters in files
    without one. PsdUtil reads both correctly.

    .EXAMPLE
    Export-Psd $config -Path ./out.psd1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [System.Collections.IDictionary] $Format,

        [ValidateRange(1, 1000)]
        [int] $Depth = 64,

        [switch] $PassThru
    )
    begin { $items = New-PsdList; $fromPipe = -not $PSBoundParameters.ContainsKey('InputObject') }
    process { $items.Add($InputObject) }
    end {
        $value = $InputObject
        if ($fromPipe) { if ($items.Count -eq 1) { $value = $items[0] } else { $value = $items.ToArray() } }
        $ctx = New-PsdContext
        $f = Get-PsdFormat $Format $ctx
        $full = Resolve-PsdUserPath $Path
        if ($ctx.Errors.Count -eq 0) {
            $text = ConvertTo-PsdTextInternal $value $f $Depth $ctx
            if ($ctx.Errors.Count -eq 0 -and $PSCmdlet.ShouldProcess($full, 'Write data file')) {
                $nl = Get-PsdNewLine $f
                $null = Write-PsdTextFile $full ($text + $nl) $f.Bom $ctx
            }
        }
        Write-PsdResult $PSCmdlet $ctx $null
        if ($PassThru -and $ctx.Errors.Count -eq 0) { Get-Item -LiteralPath $full }
    }
}
