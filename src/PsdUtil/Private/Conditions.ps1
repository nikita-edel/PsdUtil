# Decides !if conditions. They are read by PsdUtil and never run as PowerShell.

function Test-PsdCondition {
    param($Cond, $Ev)
    switch ($Cond.T) {
        'Or' { if (Test-PsdCondition $Cond.L $Ev) { return $true }; return (Test-PsdCondition $Cond.R $Ev) }
        'And' { if (-not (Test-PsdCondition $Cond.L $Ev)) { return $false }; return (Test-PsdCondition $Cond.R $Ev) }
        'Not' { return (-not (Test-PsdCondition $Cond.X $Ev)) }
        'Truth' { return (Test-PsdTruth (Get-PsdCondValue $Cond.X $Ev)) }
        'Cmp' {
            $l = Get-PsdCondValue $Cond.L $Ev
            $r = Get-PsdCondValue $Cond.R $Ev
            return (Compare-PsdCondValues $Cond $l $r $Ev)
        }
    }
    $false
}

function Get-PsdCondValue {
    param($X, $Ev)
    if ($X.T -eq 'Lit') { return , $X.V }
    $r = Invoke-PsdExpr $X.Expr $Ev $X
    , $r.Value
}

function Test-PsdTruth {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string]) { return ($Value.Length -gt 0) }
    if (Test-PsdNumber $Value) { return ($Value -ne 0) }
    if ($Value -is [System.Collections.IDictionary]) { return ($Value.PSBase.Count -gt 0) }
    if (Test-PsdList $Value) { return ($Value.Count -gt 0) }
    $true
}

function Test-PsdCondEqual {
    param($A, $B)
    if ((Test-PsdContainer $A) -or (Test-PsdContainer $B)) { return (Test-PsdEqual $A $B) }
    if ($null -eq $A) { return ($null -eq $B) }
    try { return [bool]($A -eq $B) } catch { return $false }
}

function Compare-PsdCondValues {
    param($Cond, $L, $R, $Ev)
    $ctx = $Ev.Doc.Ctx
    $op = $Cond.Op
    $bad = {
        param($msg)
        Add-PsdNodeError $ctx 'PSD402' $msg $Ev.Node $Cond.Start ($Cond.End - $Cond.Start)
        $false
    }
    switch ($op) {
        '-eq' { return (Test-PsdCondEqual $L $R) }
        '-ne' { return (-not (Test-PsdCondEqual $L $R)) }
        '-in' {
            $items = Get-PsdItems $R
            if ($R -is [System.Collections.IDictionary]) { return (& $bad "-in needs a list on the right, but it's a map.") }
            foreach ($x in $items) { if (Test-PsdCondEqual $L $x) { return $true } }
            return $false
        }
    }
    if ((Test-PsdContainer $L) -or (Test-PsdContainer $R)) {
        return (& $bad "$op can't compare $(Get-PsdKindText $L) with $(Get-PsdKindText $R). It works on text and numbers.")
    }
    switch ($op) {
        '-like' { return ((Format-PsdScalarText $L) -like (Format-PsdScalarText $R)) }
        '-match' {
            try { $rx = New-PsdRegex (Format-PsdScalarText $R) $ctx }
            catch {
                Add-PsdNodeError $ctx 'PSD403' "$(Format-PsdValueShort $R) isn't a valid regex: $($_.Exception.InnerException.Message)" $Ev.Node $Cond.Start ($Cond.End - $Cond.Start)
                return $false
            }
            try { return $rx.IsMatch((Format-PsdScalarText $L)) }
            catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
                $loc = Get-PsdNodeLoc $Ev.Node
                Add-PsdLimitError $ctx 'RegexTimeout' "by the regex in this condition" $loc.File $loc.Line $loc.Col
                return $false
            }
            catch {
                if ($_.Exception.InnerException -is [System.Text.RegularExpressions.RegexMatchTimeoutException]) {
                    $loc = Get-PsdNodeLoc $Ev.Node
                    Add-PsdLimitError $ctx 'RegexTimeout' "by the regex in this condition" $loc.File $loc.Line $loc.Col
                    return $false
                }
                throw
            }
        }
    }
    try {
        switch ($op) {
            '-gt' { return [bool]($L -gt $R) }
            '-ge' { return [bool]($L -ge $R) }
            '-lt' { return [bool]($L -lt $R) }
            '-le' { return [bool]($L -le $R) }
        }
    }
    catch {
        return (& $bad "$op can't compare $(Format-PsdValueShort $L) with $(Format-PsdValueShort $R).")
    }
    $false
}
