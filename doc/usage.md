# Using PsdUtil

PsdUtil loads, writes, merges and checks PowerShell data files (`.psd1`). It reads files without running them, and everything it adds lives in strings and special keys, so every file is still a valid `.psd1`.

Every command has help: `Get-Help Import-Psd -Full`.

## Quick start

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

`Import-Psd` returns an ordered dictionary. If anything is wrong, it reports every problem and returns nothing.

## What a file can contain

Text, numbers (`1`, `-1`, `1.5`, `0x10`, `1kb`), `$true`, `$false`, `$null`, maps `@{ }` and lists `@( )`.

Anything that would run code is rejected: variables, `"$x"`, `[int]5`, `{ script }`, `(1)` and `$(1)`. Keys have to be text, and a file has to be exactly one map.

## References

A reference is a placeholder for another value. It's written `!<...>` inside a string.

```powershell
@{
    Port     = 8080
    List     = @('a', 'b', 'c')
    'my.key' = @{ Sub = 1 }

    A = '!<Port>'                       # 8080, still a number
    B = 'port=!<Port>'                  # 'port=8080', always text
    C = '!<List[0]>'                    # 'a'
    D = '!<List[-1]>'                   # 'c', negative counts from the end
    E = '!<"my.key".Sub>'               # 1, quote keys with dots or spaces
    F = '!<Missing ?? "x">'             # 'x', used when missing or $null
    G = '!<Missing ?? Other ?? 5>'      # 5, fallbacks can be chained
    H = '!<?Missing>'                   # $null instead of an error
    I = '!<env:NOT_SET ?? "none">'      # environment variable, with a fallback
    J = 'a literal !!<Port>'            # 'a literal !<Port>'
}
```

Paths always start from the top of the file. If a reference is the whole string, it keeps the value's type. Inside longer text, `$null` becomes empty, and a map or list is an error.

### Built-ins

```powershell
'!<@name>'      # file name without extension, or its '!name'
'!<@file>'      # full path, always with /
'!<@dir>'       # folder of the file, always with /
'!<@os>'        # windows, linux or macos
```

## Filters

A filter changes a value. It goes after `|`, and filters can be chained.

```powershell
# A = '  Hello World  '
'!<A | lower>'                       # '  hello world  '
'!<A | upper>'                       # '  HELLO WORLD  '
'!<A | trim>'                        # 'Hello World'
'!<A | replace("World", "There")>'   # '  Hello There  '
'!<A | trim | split(" ")>'           # @('Hello', 'World')

# L = @('c', 'a', 'c', 'b')
'!<L | join("-")>'                   # 'c-a-c-b'
'!<L | first>'                       # 'c'
'!<L | last>'                        # 'b'
'!<L | sort>'                        # @('a', 'b', 'c', 'c')
'!<L | unique>'                      # @('c', 'a', 'b')
'!<L | count>'                       # 4

# M = @{ A = 1; B = 2 }
'!<M | keys>'                        # @('A', 'B')
'!<M | values>'                      # @(1, 2)
```

`replace` and `split` use plain text, not regex, and match case exactly. `sort` and `unique` ignore case. `$null` stays `$null`.

## Merging files

`'!merge'` puts other files underneath this one. They apply in order, and this file goes on top.

```powershell
@{
    '!merge' = @(
        './defaults.psd1'                                # a path
        './overlays/*.psd1'                              # a glob, in alphabetical order
        @{ Path = './extra.psd1'; Keys = 'Logging' }     # only certain keys
    )
}
```

Later files win:

- Maps deep merge, so only the keys you write change.
- Everything else is replaced, including lists.
- A key can change type between files. Use a schema if it shouldn't.
- `$null` sets the value to `$null`. It doesn't delete the key.

Paths are relative to the file they're written in. A file reached twice is used once. `Import-Psd -Override @{ Stage = 'prod' }` adds one more layer on top.

### Merge operators

They go after the key, with a space before them.

```powershell
'Plugins +='  = @('cache')     # add to the end
'Plugins =+'  = @('first')     # add to the start
'Plugins |='  = @('cache')     # add only what's not there yet
'Features -=' = @('beta')      # remove these items, or these keys of a map
'Old -='      = $true          # delete the key, even a whole map
'Legacy :='   = @{ C = 3 }     # replace the whole map instead of merging
```

They also work within one file: plain keys go first, then operators from top to bottom. For a nested key, nest the map: `Server = @{ 'Ports +=' = @(443) }`.

### Default operators

A key written without an operator can get one by default, from `-Merge` or from `Merge` in the schema:

```powershell
Import-Psd ./app.psd1 -Merge @{ '**' = '+=' }               # every list adds to the one below, at any depth
Merge-Psd ./base.psd1, ./app.psd1 -Merge ([ordered]@{ Plugins = '|='; 'Server.*' = '+=' })
```

```powershell
# app.schema.psd1
Plugins = @{ Type = 'string[]'; Merge = '+=' }              # Plugins = @('cache') then adds
```

Key paths use dots, `*` for one key and `**` for any number of keys. Operators: `+=`, `=+` and `|=` for lists, `:=` to replace a map instead of merging it. A default is used only where it fits: a list operator only on a list, `:=` only on a map. An operator written in the data always wins, so `'Plugins :='` still replaces and `'Plugins -='` still removes. The first `-Merge` pattern that matches wins, then the schema. `-Merge` works on `Import-Psd`, `ConvertFrom-Psd` and `Merge-Psd`.

## Including files and namespaces

`'!include'` makes another file readable without merging it. Its keys aren't in the result.

```powershell
@{
    '!include' = @('./shared.psd1', './conf.d/*.psd1')
    Database   = '!<shared::Database>'
}
```

A file's name is its file name without the extension. Set `'!name' = 'core'` in the file to use another one.

References resolve after merging. In a chain `base`, `next`, `last`:

```powershell
'!<Key>'            # Key in the final merged result
'!<@name>'          # the last file: 'last'
'!<base::Key>'      # Key in base.psd1, before merging
'!<this::Key>'      # Key in the file where this is written, before merging
'!<this::@name>'    # the file where this is written
```

A reference without `name::` reads the merged result. A key that isn't there is read from the one include that has it, `'!include'` or `-Include`, exactly as if its name were written:

```powershell
'!<Database>'       # Database of this file and its chain, else of the one include that has it
```

If several includes have the key and this file doesn't, it's error PSD313: write the name, like `!<shared::Database>`. If nothing has it, it's PSD301, with a suggestion from every include. The same holds in conditions.

When this file has the key, its value is used even if an include has the key too, and only the first key of the path decides: `!<Options.Tools>` reads `Options` of this file, never of an include. Nothing is wrong then, so it's no warning, but `-Verbose` says where each such value came from:

```
VERBOSE: app.psd1, line 3: !<Inst> reads Inst from this file and its merge chain. The include config has Inst too; !<config::Inst> reads that one.
```

A PSD301 says the same: for `!<Options.Tools>` it names the include that has `Options.Tools` and how to read it, and for a key read from an include it says which one.

An included file is its own document, so `!<@name>` inside it is that file.

### Scripts

PsdUtil runs no code, so a `.ps1` is error PSD108. With `-Loader`, `Import-Psd`, `ConvertFrom-Psd` and `Merge-Psd` read files that aren't `.psd1` through a script block you give; it gets the full path and returns a map, or an object of a generated class made from one:

```powershell
Import-Psd ./app.psd1 -Loader { param($Path) & $Path }
```

What it returns is the file: `'!merge'`, `'!include'`, `'!name'` and `'!schema'` work in it, with paths relative to its folder, and `'!merge'` and `'!include'` in any file can reach it. Each script is read once per load. Its values have no line numbers, so errors name the file.
### Maps from the caller

`-Include` passes values you only know at run time. It works on `Import-Psd`, `ConvertFrom-Psd`, `Merge-Psd`, `Test-Psd`, `Get-PsdError`, `Get-PsdProvenance` and `Resolve-PsdReference`.

```powershell
Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'prod'; Root = 'C:\app' } }
```

```powershell
@{
    Log = '!<run::Root>\log'
    '!if !<run::Stage> -eq "prod"' = @{ Replicas = 3 }
}
```

It works like `'!include'`, but the document comes from a map. Its keys aren't in the result, and the schema doesn't check them. Every file in the merge chain can read it, but files added with `'!include'` can't. The name can't be `this` or one already used by a file.

### Naming a map

A map given to `Merge-Psd` can have a name. It's used in error messages, and `!<team::Port>` and `!<@name>` work as they do for a file. Other directives are errors in maps.

```powershell
Merge-Psd ./base.psd1, @{ '!name' = 'team'; Port = 8080 }
```

## Conditions

If the condition is true, the contents are added to the map the `!if` sits in. A map can have as many as it needs.

```powershell
'!if !<Stage> -eq "prod"' = @{ Replicas = 3 }
'!if !<Stage> -ne "prod"' = @{ Replicas = 1 }
'!if !<?Feature.Enabled>' = @{ Extra = $true }
```

Operators: `-eq -ne -gt -ge -lt -le -in -like -match -and -or -not`, and `( )`. Comparisons ignore case.

A condition sees the settings from all files, but nothing inside any `!if`. A value in a later file still beats an `!if` in an earlier one.

## Schemas

A schema is a `.psd1` file. Pass it with `-Schema`, or put `'!schema' = './app.schema.psd1'` in the data file. `-Schema` wins.

```powershell
@{
    '!types' = './Types.psm1'                # only needed for your own enums

    Properties = @{
        Name  = @{ Type = 'string'; Required = $true; Pattern = '^[a-z-]+$' }
        Port  = @{ Type = 'int'; Min = 1; Max = 65535; Default = 8080; Description = 'TCP port.' }
        Stage = @{ Type = 'string'; Enum = 'dev', 'prod' }
        Level = '[LogLevel]'                 # short for @{ Type = '[LogLevel]' }
        Tags  = 'string[]'
        Host  = @{ Type = 'string', 'null' } # either one
        Db    = @{ Type = 'map'; Properties = @{ Url = 'string' }; AllowUnknown = $true }
        Limit = @{ Type = 'map'; Items = 'int' }
    }
}
```

| Keyword | Meaning |
|---|---|
| `Type` | one type or a list of types |
| `Required` | the key has to exist |
| `Description` | shown in error messages |
| `Default` | filled in by `Add-PsdDefault` |
| `Enum` | allowed values |
| `Pattern` | regex for text, case-sensitive |
| `Min`, `Max` | a number's value, text length, or list item count |
| `Properties` | the known keys of a map |
| `Items` | a rule for every list item, or every value of a free-form map |
| `AllowUnknown` | other keys are allowed too |
| `Merge` | the operator a key gets when the data writes it without one: `+=`, `=+`, `|=`, `:=` |

Types: `string`, `int`, `double`, `bool`, `map`, `array`, `any`, `null`, plus `[]` for a list, like `string[]`. Also `[version]`, `[guid]`, `[datetime]`, .NET enums like `[System.DayOfWeek]`, and your own enums through `'!types'`.

Keys not in `Properties` are errors unless `AllowUnknown` or `Items` is set.

## Generated classes

`New-PsdType` writes classes from a schema, for autocomplete in config scripts.

```powershell
New-PsdType -Schema ./app.schema.psd1 -Path ./App.Types.psm1 -Name App
```

```powershell
# app.config.ps1
using module ./App.Types.psm1

[App][ordered]@{
    Name  = 'billing'
    Stage = 'prod'
    Host  = 'db-!<Stage>'
    Db    = [AppDb]@{ Url = 'db:5432' }
    'Tags +=' = @('cache')
    '!if !<Stage> -eq "prod"' = @{ Port = 443 }
}
```

```powershell
Export-Psd -InputObject (& ./app.config.ps1) -Path ./app.psd1
```

A class made from a map keeps that map, so a typed config can use everything a data file can: references, merge operators and `!if`. A plain key that isn't a property still throws, so typos are caught.

`Export-Psd`, `ConvertTo-Psd`, `Merge-Psd` and `-Override` use the kept map. The file holds what was written, and unset properties are left out.

- Use `[App][ordered]@{ }` to keep the keys in the order you wrote them. A plain `@{ }` doesn't.
- The kept map is what gets written, so changing a property afterwards doesn't change the output.
- An object from `[App]::new()` has no kept map. It's written from its properties, and `Merge-Psd` and `-Override` don't accept it.

`-Constant` adds classes of named values, for values that are known only when the types are written. A list names each value after itself, a map gives the names:

```powershell
New-PsdType -Schema ./app.schema.psd1 -Path ./App.Types.psm1 -Name App -Constant @{
    Region = @('eu-west', 'us-east')
    Port   = @{ Http = 80; Https = 443 }
}
```

```powershell
[App]@{ Region = [Region]::eu_west; Port = [Port]::Https }     # 'eu-west' and 443, [Region]:: completes
```

Values can be text, numbers, `$true`, `$false`, `$null`, lists and maps, written as `ConvertTo-Psd` writes them and typed by their kind: `[string]`, `[int]`, `[bool]`, `[object[]]`, `[hashtable]` and so on. A character that can't be in a name becomes `_`, a name that starts with a digit gets `_` in front. Two values with one name are an error. The schema doesn't check these values, they're only for completion.

Give nested maps their own cast, or their keys won't complete. On Windows PowerShell 5.1, keys inside `@{ }` only complete after the script has run once in that session, and a relative `using module` path starts at the working directory, so run the script from its own folder.

## Commands

```powershell
# Load
Import-Psd ./app.psd1 -Schema ./app.schema.psd1 -Override @{ Stage = 'prod' }
Import-Psd ./app.psd1 -Include @{ run = @{ Stage = 'prod' } }
ConvertFrom-Psd -Text "@{ A = 1; B = '!<A>' }"
Merge-Psd ./base.psd1, ./next.psd1, @{ Tags = @('y') }
Merge-Psd ./base.psd1, ./next.psd1 -Key Logging          # returns only this key
Merge-Psd ./base.psd1, ./next.psd1 -Schema ./app.schema.psd1   # same check and messages as Import-Psd

# Write
ConvertTo-Psd $config -Format @{ Indent = 2; SortKeys = $true }
Export-Psd $config -Path ./out.psd1

# Check
Test-Psd ./app.psd1                                      # $true or $false
Get-PsdError ./app.psd1                                  # the problems, as objects
Test-PsdSchema $config -Schema ./app.schema.psd1
Add-PsdDefault $config -Schema ./app.schema.psd1         # fills in missing defaults
New-PsdSchema -FromFile ./app.psd1 -Path ./app.schema.psd1

# Keys
Test-PsdKey $config -Key Stage, 'Server.Port'            # add -Exact, -Any or -CaseSensitive
Get-PsdMissingKey $config -Key Stage, Nope
Assert-PsdKey $config -Key Stage, Nope                   # throws, listing every missing key

# Values in a loaded object
Get-PsdValue $config -Path 'Server.Port'
Set-PsdValue $config -Path 'Server.Port' -Value 9100
Remove-PsdValue $config -Path 'Plugins[0]'

# Edit a file, keeping comments
Update-Psd ./app.psd1 -Key 'Server.Port' -Value 9100
Format-Psd ./app.psd1 -Format @{ Indent = 2 }

# Debug
Compare-Psd ./base.psd1 ./app.psd1
Get-PsdProvenance ./app.psd1 -Key 'Server.Port'          # which file and line it came from
Resolve-PsdReference ./app.psd1 -Key 'Server.Url'        # how it was worked out
```

`-Format` options and their defaults:

```powershell
@{ Indent = 4; Quote = 'Single'; SortKeys = $false; AlignEquals = $false; InlineArrayMax = 4; LineEnding = 'Auto'; Bom = $false }
```

Files are written as UTF-8 without a BOM. On 5.1, plain `Import-PowerShellDataFile` misreads non-ASCII characters in those files. Set `Bom = $true` if you need that. PsdUtil reads both.

## Errors

All problems are reported together. Each one says where it is and how to fix it, and ends with a code:

```
last.psd1, line 13: 'Prot' doesn't exist under Server in base.psd1.

    BasePort = '!<base::Server.Prot>'
                               ^^^^
    Did you mean 'Port'?                                            [PSD301]
```

`-ErrorAction Stop` stops at the first one. `-UnresolvedReference` changes what a missing key does: `Error` is the default, `Warn` gives a warning and `$null`, `Null` gives `$null` silently, and `Keep` leaves the reference as written.

| Codes | Area |
|---|---|
| PSD100–108 | reading a file |
| PSD200–212 | merging, including, directives, operators |
| PSD300–313 | references and filters |
| PSD400–403 | conditions |
| PSD500–515 | schemas |
| PSD600–607 | writing and editing |
| PSD700 | a limit was reached |

## Limits

Loading always finishes: there are no loops or user-defined functions, and cycles are errors. Change a limit with `-Limits @{ MaxDepth = 128 }`.

| Limit | Default |
|---|---|
| `MaxDepth` | 64 |
| `MaxFiles` | 256 |
| `MaxFileSize` | 100MB |
| `MaxStringLength` | 1MB |
| `MaxNodes` | 100000 |
| `RegexTimeout` | 1 second |
