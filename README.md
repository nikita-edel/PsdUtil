# PsdUtil

Reads, writes, merges and checks PowerShell data files (`.psd1`) for configuration. 

```powershell
# base.psd1
@{
    Stage  = '!<env:APP_STAGE ?? "dev">'
    Server = @{
        Host = 'localhost'
        Port = 8080
        Url  = 'http://!<Server.Host>:!<Server.Port>'
    }
    Plugins = @('core')
    '!if !<Stage> -eq "prod"' = @{ Server = @{ Port = 443 } }
}

# app.psd1
@{
    '!merge'     = './base.psd1'
    Server       = @{ Host = 'example.local' }
    'Plugins +=' = @('cache')
}
```

```powershell
Import-Module PsdUtil
$config = Import-Psd ./app.psd1
$config.Server.Url      # http://example.local:8080
$config.Plugins         # core, cache
```

## What's in it

- **References:** `!<Server.Port>`, fallbacks `!<A ?? "x">`, optional `!<?A>`, `!<env:NAME>`, built-ins `@name`, `@file`, `@dir`, `@os`, and [filters](doc/usage.md#filters) like `!<Name | lower>`.
- **Merging and including:** `'!merge'` and `'!include'` with paths and globs, namespaces like `!<base::Port>` and `!<this::@name>`, and the operators `+=`, `=+`, `|=`, `-=`, `:=`.
- **Conditions:** `'!if !<Stage> -eq "prod"' = @{ ... }`.
- **Schemas** written as `.psd1`, with types, enums, patterns, ranges and required keys. Errors name the file, line and key, underline the problem and suggest a fix.
- **Writing:** `ConvertTo-Psd`, `Export-Psd`, and `Update-Psd` and `Format-Psd`, which keep comments.
- **Typed configs:** `New-PsdType` writes classes from a schema, for autocomplete in config scripts.

Every command has help: `Get-Help Import-Psd -Full`. The full guide is in [doc/usage.md](doc/usage.md).

| Command | Purpose |
|---|---|
| `Import-Psd`, `ConvertFrom-Psd` | Load a file or text |
| `ConvertTo-Psd`, `Export-Psd` | Write an object as text or a file |
| `Merge-Psd` | Merge files and maps in order |
| `Test-Psd`, `Get-PsdError` | Check a file |
| `Test-PsdSchema`, `Add-PsdDefault`, `New-PsdSchema` | Schemas |
| `Test-PsdKey`, `Get-PsdMissingKey`, `Assert-PsdKey` | Check keys |
| `Get-PsdValue`, `Set-PsdValue`, `Remove-PsdValue` | Values by path |
| `Update-Psd`, `Format-Psd` | Edit files in place |
| `New-PsdType` | Classes from a schema |
| `Compare-Psd`, `Get-PsdProvenance`, `Resolve-PsdReference` | Debugging |

## Install

From a release zip: unpack it and run `./install.ps1`. It copies the module to your user module folder, for both 5.1 and 7 on Windows.<br>
PsGallery: `Install-Module PsdUtil`
