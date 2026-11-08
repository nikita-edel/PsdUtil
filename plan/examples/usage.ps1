# Every command, run against the files in config/
# The values in the comments are what you get (see config/result.psd1).

# --- Load ---------------------------------------------------------------------

$config = Import-Psd ./config/last.psd1

$config.Service.Name        # last
$config.Service.Origin      # base
$config.Server.Port         # 9000
$config.BasePort            # 8080

# -Override is one more layer on top.
# Stage turns on the !if in base.psd1, which sits in base's layer:
$prod = Import-Psd ./config/last.psd1 -Override @{ Stage = 'prod' }

$prod.Server.Tls.Enabled    # True    set by the !if in base
$prod.Server.Port           # 9000    next.psd1 is above base, so it still wins
$prod.Plugins               # core, auth, metrics, cache

# A missing key is an error by default.
Import-Psd ./config/last.psd1 -UnresolvedReference Warn

ConvertFrom-Psd -Text "@{ A = 1; B = '!<A>' }"      # A = 1, B = 1


# --- Merge --------------------------------------------------------------------

# Same rules as !merge. Later wins. Files and maps can be mixed.
Merge-Psd ./config/base.psd1, ./config/next.psd1, @{ Tags = @('y') }

# Only certain keys.
Merge-Psd ./config/base.psd1, ./config/extra.psd1 -Key Logging


# --- Check --------------------------------------------------------------------

Test-Psd ./config/last.psd1                                 # True
Get-PsdError ./config/last.psd1 -Schema ./config/app.schema.psd1            # the errors
Test-PsdSchema $config -Schema ./config/app.schema.psd1     # True

Test-PsdKey $config -Key Stage, 'Server.Port'               # True
Get-PsdMissingKey $config -Key Stage, Nope                  # Nope
Test-PsdKey $config.Server.Tls -Key Enabled, Port -Exact    # True
Test-PsdKey $config -Key Foo, Stage -Any                    # True

Assert-PsdKey $config -Key Stage, Nope, 'Server.Nope'       # throws, listing both

Get-PsdValue $config -Path 'Server.Tls.Port'                # 9000
Get-PsdValue $config -Path 'Plugins[-1]'                    # cache

Set-PsdValue $config -Path 'Server.Port' -Value 9100        # only in memory
Remove-PsdValue $config -Path 'Token'

Add-PsdDefault $config -Schema ./config/app.schema.psd1     # fills in missing defaults


# --- Write --------------------------------------------------------------------

ConvertTo-Psd $config
ConvertTo-Psd $config -Format @{ Indent = 2; SortKeys = $true }
Export-Psd $config -Path ./out.psd1

# Changes the value only. Comments and formatting stay.
Update-Psd ./config/next.psd1 -Key 'Server.Port' -Value 9100

# Reformats the file. Comments stay.
Format-Psd ./config/next.psd1 -Format @{ Indent = 2 }


# --- Debug --------------------------------------------------------------------

Get-PsdProvenance ./config/last.psd1 -Key 'Server.Port'
#   Key         Value  Source          Overrides
#   ---         -----  ------          ---------
#   Server.Port  9000  next.psd1:5:24  base.psd1:19:16

# How one reference is worked out.
Resolve-PsdReference ./config/last.psd1 -Key 'Service.Title'
#   Service.Title   '!<Service.Name | upper> (!<Stage>)'
#   Service.Name    '!<@name>'    -> last
#   | upper                       -> LAST
#   Stage           '!<env:APP_STAGE ?? "dev">'    -> dev
#   result          LAST (dev)

# What differs between two files or objects.
Compare-Psd ./config/base.psd1 ./config/next.psd1
#   Path         Change   Left   Right
#   ----         ------   ----   -----
#   Server.Port  changed  8080   9000


# --- Types --------------------------------------------------------------------

New-PsdSchema -FromFile ./config/last.psd1 -Path ./starter.schema.psd1

New-PsdType -Schema ./config/app.schema.psd1 -Path ./typed/App.Types.psm1 -Name App

# Run from its own folder: on 5.1, using module paths start at the working directory.
Push-Location ./typed
Export-Psd -InputObject (& ./app.config.ps1) -Path ./app.psd1
Pop-Location
