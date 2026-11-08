function Format-Psd {
    <#
    .SYNOPSIS
    Re-indents a .psd1 file by nesting depth. Comments and text stay as they are.

    .DESCRIPTION
    Uses Indent, AlignEquals, LineEnding and Bom from -Format. LineEnding 'Auto' keeps the
    file's own line endings, and the byte order mark is kept unless Bom is given.

    .EXAMPLE
    Format-Psd ./next.psd1 -Format @{ Indent = 2 }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [System.Collections.IDictionary] $Format
    )
    process {
        $ctx = New-PsdContext
        $f = Get-PsdFormat $Format $ctx
        $bomGiven = $false
        if ($Format) { foreach ($k in $Format.PSBase.Keys) { if ([string]$k -ieq 'Bom') { $bomGiven = $true } } }
        $full = Resolve-PsdUserPath $Path
        if ($ctx.Errors.Count -eq 0 -and $PSCmdlet.ShouldProcess($full, 'Reformat')) {
            $null = Format-PsdFileText $full $f $bomGiven $ctx
        }
        Write-PsdResult $PSCmdlet $ctx $null
    }
}
