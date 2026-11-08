# PsdUtil – Design

What PsdUtil does and how it behaves. How it gets built: `IMPLEMENTATION.md`. What it looks like: `examples/`. All filters: `filters.md`.

*(tested)* means it was run on PowerShell 5.1.26100 and 7.6.7.

## 1. Constraints

- Pure script module, no dependencies, no C#. Runs on 5.1 and 7, on Windows, Linux and macOS.
- No JSON support of any kind.
- About 4100 lines of code in `src/`, not counting help and comments. The first estimate was 2400.
- First use: a configuration system.
- Every file stays a valid `.psd1`. All grammar lives in strings and special keys.
- Data files never execute code, and loading a file always finishes.

## 2. Commands

**Load and write**

| Command | Purpose |
|---|---|
| `Import-Psd` | Load a file through the full pipeline. `-Schema`, `-Override`, `-UnresolvedReference Error\|Warn\|Null\|Keep`, `-Limits` |
| `ConvertFrom-Psd` | Same, from a string. `-BasePath` for relative paths |
| `ConvertTo-Psd` | Object to psd text. `-Format`, `-Depth` |
| `Export-Psd` | Object to psd file. `-Format`, `-Depth` |
| `Merge-Psd` | Ordered merge of n files or maps. `-Key` returns only those keys; everything is still merged, so references work |

**Check**

| Command | Purpose |
|---|---|
| `Test-Psd` | Is the file valid (syntax, references, schema)? Returns a bool. `-Raw` also checks each file on its own |
| `Get-PsdError` | The errors `Test-Psd` found |
| `Test-PsdSchema` | Check an object already in memory against a schema |
| `Test-PsdKey` | Keys present? Nested paths, `-Exact`, `-Any`, `-CaseSensitive` |
| `Get-PsdMissingKey` | Which of these keys are missing |
| `Assert-PsdKey` | Same checks, throws one error listing every missing key |

**Read and change values**

| Command | Purpose |
|---|---|
| `Get-PsdValue` | Read a value by path |
| `Set-PsdValue` | Change a value in a loaded object by path |
| `Remove-PsdValue` | Remove a value from a loaded object by path |
| `Update-Psd` | Change a value in a file, keeping comments and formatting |
| `Format-Psd` | Reformat a file, keeping comments |

**Schema tools**

| Command | Purpose |
|---|---|
| `Add-PsdDefault` | Fill in the schema's `Default` values |
| `New-PsdSchema` | Starting schema from a sample file |
| `New-PsdType` | Generate classes from a schema for autocomplete |

**Debug**

| Command | Purpose |
|---|---|
| `Compare-Psd` | What was added, removed or changed between two files or objects |
| `Resolve-PsdReference` | How one reference is worked out, step by step |
| `Get-PsdProvenance` | Which file and line each value came from, and what it overrode |

`-Key` and `-Path` parameters use the same path syntax as references.

`Import-Psd` always returns an ordered dictionary, which also binds to `[hashtable]` parameters *(tested)*.

## 3. Pipeline

One fixed order:

```
1. Parse       each file to a tree of values with file, line and column
2. Load        follow !merge and !include, expand globs, detect cycles
3. Conditions  merge everything without any !if, decide each !if against that,
               put the true ones into their file's layer
4. Merge       apply the layers in order. List operators are recorded on the key
5. Resolve     work out references on demand, then apply the recorded list operators
6. Validate    schema, against the final result
7. Output      ordered dictionary
```

## 4. Parsing

Read with `[IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)`, then `Parser::ParseInput($text, $path, ...)`. `ParseFile` can't be used: on 5.1 it misreads UTF-8 without a BOM *(tested)*.

Then walk the AST against an allow-list:

| Accepted | Rejected |
|---|---|
| strings, including double-quoted without `$` | `$env:X`, `"x$y"`, any other variable |
| numbers: `1`, `-1`, `1.5`, `0x10`, `1kb` | casts: `[int]5` |
| `$true`, `$false`, `$null` | script blocks: `{ ... }` |
| `@{ }`, `@( )`, `1,2` | `(1)`, `$(1)` |
| string keys | numeric keys: `@{ 1 = 'x' }` |
| exactly one root hashtable | a second root statement |

The right column is stricter than `Import-PowerShellDataFile`, which accepts casts, script blocks, `(1)`, `$(1)`, numeric keys and a second root *(tested)*.

Duplicate keys, including `a` and `A`, are already a parse error from PowerShell, with a position *(tested)*.

## 5. References

| Form | Meaning |
|---|---|
| `!<A.B.C>` | key path from the root |
| `!<List[0]>`, `!<List[-1]>` | array index, negative counts from the end |
| `!<"my.key".Sub>` | key with dots or spaces. A literal `"` is doubled |
| `!<Key ?? "x">` | fallback when missing or `$null`, can be chained |
| `!<?Key>` | short for `!<Key ?? null>` |
| `!<env:NAME>` | environment variable |
| `!<A \| lower>` | a filter, see `filters.md` |
| `!!<` | a literal `!<` |

| Built-in | Value |
|---|---|
| `!<@name>` | file name without extension, or its `!name` |
| `!<@file>` | full path |
| `!<@dir>` | directory of the file, no trailing slash |
| `!<@os>` | `windows`, `linux` or `macos` |

`@file` and `@dir` always use `/`.

Rules:

- `'!<A.B>'` as the whole string keeps the type (map, array, int).
- `'x-!<A.B>-y'` always produces a string. A map or array there is PSD306.
- Inside a string, `$null` becomes empty and numbers use invariant culture.
- References resolve through other references.
- Going through a `$null` counts as a missing key: `!<Server.Port>` is an error when `Server` is `$null`, while `?` and `??` work normally.
- A missing key is an error with a "did you mean", using edit distance against keys at that level.
- `-UnresolvedReference` changes that for the whole load: `Warn` gives a warning and `$null`, `Null` gives `$null` silently, `Keep` leaves the reference text as it is written.
- A reference starts with a key, so `!<"my.key">` reads the key `my.key`. Later in a reference, like after `??` or as a filter argument, `"text"` is text, unless `.` or `[` follows it: `!<A ?? "my.key".Sub>`.
- Keys can't contain references (PSD305), so paths and schemas stay static.

## 6. Files and namespaces

Chain `base`, `next`, `last`, where each file merges the one before it:

| Written anywhere in the chain | Resolves to |
|---|---|
| `!<Key>` | `Key` in the final merged result |
| `!<@name>` | built-in of the **last** file, so `last` |
| `!<this::Key>` | `Key` in the file where this is written, before merging |
| `!<this::@name>` | built-in of the file where this is written |
| `!<base::Key>` | `Key` in `base`, before merging |

1. A namespace chooses which value. References inside that value still resolve by the rules above.
2. Every file in a merge chain has a namespace, but using it is optional.
3. Included files are always namespaced. `!<Key>` never finds a key in an included file.
4. An included file is its own document with its own chain. In it, `!<@name>` is the included file.
5. Directives are per file and are never merged.
6. A file's namespace is its name without extension, or its `'!name'`, which also changes `@name`. Everything before `::` is the namespace, so `base.dev::Key` works.

| Directive | Value |
|---|---|
| `'!merge'` | path, glob, or `@{ Path = '...'; Keys = 'A','B' }`, or a list of those. Applied in order, then this file on top |
| `'!include'` | path, glob, or a list |
| `'!name'` | namespace of this file |
| `'!schema'` | schema path. `-Schema` wins over it |
| `'!if <condition>'` | section 8 |

`!types` also exists, in schemas only (section 10).

Every key starting with `!` is reserved. A real key that starts with `!` is written `'!!key'`.

Paths inside a file are relative to that file. Globs expand alphabetically. No URLs.

## 7. Merging

Later wins.

| Earlier \ Later | scalar | array | map |
|---|---|---|---|
| scalar | replace | replace | replace |
| array | replace | **replace** | replace |
| map | replace | replace | **deep merge** |

- A type change between layers is not an error. If a key can't change type, the schema says so.
- A value that is a reference counts as plain text here. It isn't looked into.
- `$null` sets the key to `$null`, replacing a map or list completely. It doesn't delete the key.
- `Import-Psd -Override @{ Stage = 'prod' }` is one more layer on top. There is no separate variable syntax.

Merge operators are written after the key, separated by a space:

```powershell
'Plugins +='  = @('cache')    # add to the end
'Plugins =+'  = @('first')    # add to the start
'Plugins |='  = @('cache')    # add only what's not there yet
'Features -=' = @('beta')     # remove these items, or these keys of a map
'Old -='      = $true         # delete the key, even a whole map
'Legacy :='   = @{ C = 3 }    # replace the whole map instead of merging
```

- They work on earlier files and in the same file. A file's plain keys go first, then its operators from top to bottom.
- They work inside an `!if` body.
- The key is a key of the map it's in. For a nested key, nest the map: `Server = @{ 'Ports +=' = @(80) }`.
- `+=`, `=+` and `|=` on a key that doesn't exist or is `$null` start from an empty list.
- `|=` and `-=` compare final values, after references are worked out. Two `'!<this::@name>'` from different files are different items.
- Replacing a list needs no operator, just write the new list.
- A real key can't end in a space plus one of these operators.

## 8. Conditions

```powershell
'!if !<Stage> -eq "prod"' = @{ Replicas = 3 }
'!if !<Stage> -ne "prod"' = @{ Replicas = 1 }
'!if !<?Feature.Enabled>' = @{ Extra = $true }
```

- If the condition is true, its contents are added to the map the `!if` sits in. A map can have as many as needed. There is no else or switch.
- Anything read from a key is a normal reference, so `env:`, `@os`, `?` and `??` all work.
- Operators: `-eq -ne -gt -ge -lt -le -in -like -match -and -or -not`, and `( )`. Comparisons ignore case.
- It's read by PsdUtil and never run as PowerShell.
- A condition sees the settings from all files, but nothing inside any `!if`. So `base` can test a `Stage` set in `last`, a value in `last` still beats an `!if` in `base`, conditions can't form circles, and their order never matters.

## 9. Grammar

```
ref       = "!<" expr ">"
expr      = operand { "??" operand } { "|" filter }
operand   = [ "?" ] path | string | number | "true" | "false" | "null"
path      = [ scope ] ( "@" name | key { "." key | "[" int "]" } )
scope     = "env:" | namespace "::"
key       = name | string
filter    = name [ "(" expr { "," expr } ")" ]

condition = and { "-or" and }
and       = not { "-and" not }
not       = [ "-not" ] compare
compare   = "(" condition ")" | value [ op value ]
value     = ref | string | number | "true" | "false" | "null"
op        = "-eq" | "-ne" | "-gt" | "-ge" | "-lt" | "-le" | "-in" | "-like" | "-match"
```

## 10. Schema

A `.psd1` file loaded with `Import-Psd`, so `!include` and references work in it. That gives reusable sub-schemas with no extra feature. Every keyword in one file: `examples/schema-keywords.psd1`.

| Keyword | Applies to | Meaning |
|---|---|---|
| `Type` | all | one type or a list of types |
| `Required` | all | key must exist |
| `Description` | all | shown in errors |
| `Default` | all | used by `Add-PsdDefault` |
| `Enum` | all | allowed values, generates an enum |
| `Pattern` | string | regex, case-sensitive. Add `(?i)` to ignore case |
| `Min`, `Max` | int, double, string, array | value, length, or item count |
| `Properties` | map | known keys |
| `Items` | array, map | rule for every item, or every value of a free-form map |
| `AllowUnknown` | map | don't error on other keys |

A plain string is short for a type: `Port = 'int'` means `Port = @{ Type = 'int' }`.

Types:

- `string`, `int`, `double`, `bool`, `map`, `array`, `any`, `null`, plus `[]` (`string[]`).
- Several at once: `Type = 'string','map'`.
- `[version]`, `[guid]`, `[datetime]`: the value stays a string and only has to convert.
- An enum: `'[LogLevel]'`, or `'[LogLevel][]'` for a list. All its members become the allowed values.

Enums:

- .NET enums resolve by name: `'[System.DayOfWeek]'`.
- PowerShell enums can't be found by name, even after `Import-Module` *(tested)*. The schema points to the file with `'!types' = './Types.psm1'`, and the members are read from its AST, so no code runs *(tested)*.
- Data files use the member name as a string: `Level = 'Warn'`, ignoring case. `[LogLevel]::Warn` is not valid in a `.psd1` *(tested)*. In a typed `.ps1` it works normally.
- A value must be one member name. Numbers and flag combinations like `'A,B'` are not accepted.

Behaviour:

- Validates the final result.
- Only validates. `Add-PsdDefault` fills in defaults.
- Unknown keys are errors with a "did you mean", which also catches typos in data.
- No custom validators, since loading never runs code. Other rules go in your own code after `Import-Psd`.

## 11. Generated types

`New-PsdType` writes one `.psm1` with classes and enums. Regenerated manually.

| How you write it, with `using module` | 5.1 | 7 |
|---|---|---|
| `[App]@{ <TAB>` keys | after one run | yes |
| `[App]@{ Server = [AppServer]@{ <TAB>` nested keys | after one run | yes |
| `[App]@{ Server = @{ <TAB>` nested without a cast | no | no |
| `$c = [App]::new(); $c.<TAB>` | yes | yes |
| `$c.Server.<TAB>` second level | no | no |
| `[AppStage]::<TAB>` enum values | yes | yes |
| `Stage = '<TAB>` enum as a string | no | no |

*(tested with `TabExpansion2`)* "After one run" means the config script has run once in that session. `Import-Module` isn't enough.

Generator rules:

- Value types are `[Nullable[T]]`. A plain `[int]` or enum property defaults to a value and would be written even if never set *(tested)*.
- `Export-Psd` skips `$null` properties on class instances.
- A key with several types becomes `[object]`. Its nested class is still generated, so a cast still completes.
- A key with a dot becomes `${my.key}` *(tested)*.
- An enum from `!types` is copied into the generated file. A `using module` inside the generated file wouldn't make it visible to your script *(tested)*.

Using them:

- The `.ps1` file is real PowerShell, so it uses variables. `'!<...>'` only fits string properties.
- On 5.1, a relative `using module` path resolves from the working directory, on 7 from the script *(tested)*. Run config scripts from their own folder.
- Unknown properties and bad enum values already fail when the object is created *(tested)*.

## 12. Writing files

`-Format` takes a map. Defaults:

```powershell
@{ Indent = 4; Quote = 'Single'; SortKeys = $false; AlignEquals = $false; InlineArrayMax = 4; LineEnding = 'Auto'; Bom = $false }
```

Files are UTF-8 without a BOM. On 5.1, plain `Import-PowerShellDataFile` misreads non-ASCII characters in those files *(tested)*. PsdUtil reads them correctly.

| Input | Output |
|---|---|
| map, ordered map, PSCustomObject, class instance | `@{ }` |
| array, list | `@( )`, also for 0 or 1 items |
| string, number, bool, `$null` | literal, `'` escaped as `''` |
| keys | bare when possible, quoted when they need it |
| text containing `!<`, keys starting with `!` | escaped as `!!<` and `'!!key'`, so the file reads back the same |
| `DateTime` | ISO-8601 string |
| `Guid`, `Version`, `Uri` | string |
| enum | name as a string |
| `ScriptBlock`, `SecureString` | error |
| other objects | map of public properties up to `-Depth` |
| leaf with no usable properties | `ToString()` and a warning |

Cycles are detected by object identity and reported with their path. `-Depth` defaults to 64. `ConvertTo-Psd | ConvertFrom-Psd` gives an equal object.

`Update-Psd` replaces only the text of the value, using AST positions. A new key goes before the closing `}` with the indent of its siblings. It edits that one file and doesn't follow chains. A file that doesn't parse is left untouched.

## 13. Limits

The grammar has no loops, no recursion and no user-defined functions. Filters are a fixed list, each reference is worked out once, and cycles are errors. Pass `-Limits` to change any of these.

| Limit | Default | Protects against |
|---|---|---|
| `MaxDepth` | 64 | deep reference chains and nesting |
| `MaxFiles` | 256 | huge includes and globs |
| `MaxFileSize` | 100MB | oversized input |
| `MaxStringLength` | 1MB | `A='!<B>!<B>'`, `B='!<C>!<C>'` doubling |
| `MaxNodes` | 100000 | the same doubling through maps and arrays. Counts only values created by references, not values in the files |
| `RegexTimeout` | 1 second | a `-match` or `Pattern` regex that would otherwise run for hours *(tested)* |

## 14. Errors

Each error has a code, file, line, column, key path, message and an optional hint. They are real `ErrorRecord`s, so `-ErrorAction` and `-ErrorVariable` work. All errors are collected and reported together. `-ErrorAction Stop` fails on the first.

Every message reads like this (examples: `examples/errors.txt`):

1. File and line, then one plain sentence saying what's wrong, using your key names.
2. The source line with the problem underlined.
3. One line on how to fix it: "did you mean", the allowed values, or the schema `Description`.
4. The code last, in brackets. The message must make sense without it.

No internal words like node, token or AST. Keys with dots are shown quoted, here and in provenance.

Each row has at least one case in `tests/Errors.Tests.ps1`. A code listed here without a case fails the tests.

**Parse**

| Code | Trigger |
|---|---|
| PSD100 | file not found or unreadable |
| PSD101 | PowerShell syntax error |
| PSD102 | duplicate key, including different case |
| PSD103 | empty or comment-only file, or root is not a hashtable |
| PSD104 | more than one root statement |
| PSD105 | rejected expression (section 4) |
| PSD106 | non-string key |
| PSD107 | invalid UTF-8 in the file |

**Load and merge**

| Code | Trigger |
|---|---|
| PSD200 | merged or included file not found |
| PSD201 | cycle through `!merge` or `!include`, including a file loading itself |
| PSD202 | glob matched nothing |
| PSD203 | two different files with the same namespace |
| PSD204 | a file's namespace is the reserved `this` |
| PSD205 | unknown directive (any unrecognised `!key`), or `!types` outside a schema |
| PSD206 | directive has the wrong shape |
| PSD207 | `Keys` names a key that isn't in the file |
| PSD208 | URL given as a path |
| PSD209 | key ends in something close to an operator, like `=-` or `++` |
| PSD210 | operator used on the wrong kind of value, like `+=` on a map |
| PSD211 | operator given the wrong kind of value, like `-=` with a number |
| PSD212 | `-=` on a key or item that doesn't exist |

**References**

| Code | Trigger |
|---|---|
| PSD300 | malformed reference: unclosed, empty `!<>`, nested, bad token, with exact column |
| PSD301 | key not found, or the path goes through a `$null` |
| PSD302 | unknown namespace, or a file that isn't in the chain or included |
| PSD303 | cycle, with the full path: `A.x -> B.y -> A.x`. Includes self-reference and referencing a parent that contains the reference |
| PSD304 | path goes through a scalar: `!<Name.Sub>` where `Name` is a string |
| PSD305 | reference in a key |
| PSD306 | map or array used inside a larger string |
| PSD307 | array index out of range |
| PSD308 | index on a non-array, or key on an array |
| PSD309 | unknown built-in |
| PSD310 | environment variable not set |
| PSD311 | unknown filter |
| PSD312 | filter got the wrong type or number of arguments |

**Conditions**

| Code | Trigger |
|---|---|
| PSD400 | malformed condition |
| PSD401 | condition uses a key that only exists inside an `!if` body |
| PSD402 | incomparable types, like a map with `-gt` |
| PSD403 | invalid regex in `-match` |

**Schema**

| Code | Trigger |
|---|---|
| PSD500 | schema file is invalid |
| PSD501 | wrong type |
| PSD502 | required key missing |
| PSD503 | unknown key |
| PSD504 | value not in `Enum` |
| PSD505 | value doesn't match `Pattern` |
| PSD506 | outside `Min` or `Max` |
| PSD507 | invalid regex in `Pattern` |
| PSD508 | `Default` doesn't satisfy its own rules |
| PSD509 | unknown type name |
| PSD510 | `Min` is greater than `Max` |
| PSD511 | `!schema` file not found |
| PSD512 | type name would generate an invalid class name (`New-PsdType`) |
| PSD513 | `[Name]` is not a known enum or supported type |
| PSD514 | `!types` file not found or doesn't parse |
| PSD515 | same enum name in two `!types` files |

**Output**

| Code | Trigger |
|---|---|
| PSD600 | cycle in the object graph |
| PSD601 | `-Depth` exceeded |
| PSD602 | type that can't be written (`ScriptBlock`, `SecureString`) |
| PSD603 | key can't be converted to a string, or ends in a merge operator |
| PSD604 | invalid `-Format` option |
| PSD605 | target file can't be written |
| PSD606 | `Update-Psd` on a file that doesn't parse |
| PSD607 | `Update-Psd` path doesn't exist or passes through a scalar |

**Limits**

| Code | Trigger |
|---|---|
| PSD700 | any limit from section 13, naming the limit and where it was hit |

**Not errors, but each needs a test**

- `!<A>` on a `$null` value is fine, on a missing key it's PSD301.
- The same file reached twice in a chain or include tree is loaded once.
- Relative paths in nested files resolve from the file they're in, not the working directory.
- A reference whose target was removed gives PSD301 naming the file that removed it.
- Keys with dots, spaces, unicode, and strings containing `>` in quoted parts.
- Single-item and empty arrays survive every step.
- UTF-8 with and without BOM. CRLF and LF.
- Number types are preserved through references (`int` stays `int`).
- Pulling a map in through a reference copies it, so nothing is shared in the result.
- `|=` and `-=` on items that only match after references are worked out.
- A later map over an earlier `$null` doesn't bring the old keys back.

## 15. Repo

```
src/PsdUtil/   PsdUtil.psd1, PsdUtil.psm1, Public/, Private/
tests/         PsdUtil.Tests.ps1, Errors.Tests.ps1, Helpers.ps1
examples/
script/        update_subtree.ps1
build.ps1      -Task Test | Analyze | Package | Publish
install.ps1
.github/workflows/release.yml
PSScriptAnalyzerSettings.psd1
CHANGELOG.txt
README.md
```

- `Test`: Pester 5 or newer, with code coverage. `-NoCoverage` skips it.
- `Analyze`: PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`, including the 5.1 syntax check.
- `Package`: `dist/PsdUtil-<version>.zip` containing the module and `install.ps1`.
- `install.ps1`: copies the module to the user's module path for 5.1 and 7, or for 7 on Linux and macOS.
- `Publish`: `Publish-Module` to the PowerShell Gallery, key from `$env:PSGALLERY_KEY`.
- `script/update_subtree.ps1`: updates the `psdutil` branch from `src/PsdUtil`, then you push it. Same as `nsl_pp`.
- `release.yml`: releases the latest `v*` tag, on a tag push or by hand. It checks the tag matches `ModuleVersion`, publishes to the PowerShell Gallery with the repository secret `PSGALLERY_KEY`, then creates a GitHub release titled with the tag. The text is what was added to `CHANGELOG.txt` since the latest release, or the whole file for the first one. No tests run in GitHub; run `./build.ps1` before tagging.

### Using it as a submodule

The `psdutil` branch has only the contents of `src/PsdUtil`, with the manifest at its root.

```
[submodule "src/PsdUtil"]
    path = src/PsdUtil
    url = git@github.com:nikita-edel/PsdUtil.git
    branch = psdutil
```

The repo's `src/` works like an include path. It goes on the module path once, then the module is imported by name *(tested)*:

```powershell
$env:PSModulePath = "$PSScriptRoot/src" + [IO.Path]::PathSeparator + $env:PSModulePath

Import-Module PsdUtil
```

- The folder has to be named `PsdUtil`.
- Never force-push `psdutil` or edit it by hand. Other repos pin its commits.
