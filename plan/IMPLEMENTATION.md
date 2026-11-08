# PsdUtil – Implementation

How it gets built, in order. What it has to do is in `DESIGN.md`.

Each step ends with something that can be run and tested. No step starts until the one before passes on both 5.1 and 7.

**Status: all 11 steps are done.** 157 tests pass on PowerShell 5.1 and 7.6, code coverage is 83%, PSScriptAnalyzer finds nothing. Linux and macOS run in CI only; they weren't tested locally.

## Rules while building

*(tested)* means it was run on PowerShell 5.1 and 7.

- **No 7-only syntax:** no `??`, `?.`, `? :` or `&&` in the code. PSScriptAnalyzer's `PSUseCompatibleSyntax` checks this against 5.1.
- **Source files are ASCII only**, because 5.1 misreads non-ASCII in UTF-8 files without a BOM *(tested)*.
- **Lists stay in `List[object]` inside the module.** PowerShell breaks plain arrays on return: `return @('x')` gives a string and `return @()` gives `$null` *(tested)*. Functions that return a list use `return ,$list` *(tested)*. Only the output step makes normal arrays.
- **No classes in the module**, so it reloads cleanly. Values are plain hashtables.
- `Set-StrictMode -Version 3.0` in the module.
- Every error goes through one function, so the format in `DESIGN.md` section 14 can't drift.
- Every error code gets its test case in the same step that adds the code.
- **Never `@($list)` on a `List[object]`.** It throws "Argument types do not match" on 5.1 and 7 *(tested)*. Use `Get-PsdItems` or `foreach`.
- **Map keys go through `.PSBase.Keys`.** `$map.Keys` returns the value of a key called `Keys` if the map has one, which user data can *(tested)*. Same for `.Count` and `.Values`.
- **Strict mode throws on a missing hashtable key** read as a property *(tested)*, so internal records are created with every field.
- **No `GetFullPath` on paths with `*`**: .NET Framework rejects them *(tested)*.

## Layout

Lines of code as built, without help, comments and blank lines. The estimate in brackets was the plan.

| File in `src/PsdUtil/Private/` | Does | Lines |
|---|---|---|
| `Errors.ps1` | context, error format, collecting errors, did-you-mean, shared helpers | 291 (130) |
| `Reader.ps1` | text and objects to a value tree, the allow-list, keys and directives | 506 (120) |
| `Grammar.ps1` | parser for references, conditions and paths | 397 (250) |
| `Path.ps1` and `KeyCheck.ps1` | walking, setting and removing paths in plain objects, key checks | 157 (60) |
| `Loader.ps1` | `!merge`, `!include`, globs, namespaces, file cycles | 266 (150) |
| `Merger.ps1` | layers, deep merge, operators | 164 (130) |
| `Conditions.ps1` | evaluating `!if` | 96 (60) |
| `Resolver.ps1` | references, built-ins, list operators, limits | 389 (200) |
| `Filters.ps1` | the 13 filters | 103 (60) |
| `Writer.ps1` | object to psd text | 243 (130) |
| `Schema.ps1` | rules, validation, enums, defaults, inference | 422 (220) |
| `TypeGen.ps1` | classes from a schema | 154 (130) |
| `FileEdit.ps1` | `Update-Psd` and `Format-Psd` | 209 (230) |
| `Debug.ps1` and `Pipeline.ps1` | compare, provenance, tracing, the full load | 174 (210) |
| `Public/*.ps1` and `PsdUtil.psm1` | the 22 commands | 524 (350) |
| | **Total** | **4095 (2400)** |

The reader, resolver and schema grew most: they hold the directive checks, the source positions for underlining, and most of the error messages.

## How the pieces fit

**A value in the tree** is a hashtable: `Kind` (`Scalar`, `Text`, `List`, `Map`), `Value`, `File`, `Line`, `Column`, `Path`. `Text` means a string containing a reference, and it holds its parsed form. Merging adds `Origin` and `Overrides`, which is all provenance needs.

**A document** is one loaded chain: its layers in order, its namespaces, and the merged tree. An included file is another document.

**Conditions** reuse the merger. Merge the layers with every `!if` removed, decide each `!if` against that result, put the true bodies into their layers, then merge again for real.

**Resolving** is one recursive function with a cache and a "currently resolving" list. A value is worked out the first time something asks for it. If it's already in the list, that's a cycle, and the list is the path shown in the error. Recursion is safe because `MaxDepth` is 64, far below where PowerShell overflows *(tested)*.

**List operators** are stored on the key during merging and run when that key is resolved, so `|=` and `-=` compare final values. Map changes (`:=`, deep merge, deleting a key) happen during merging.

**The schema** walks the value tree, not the plain output, so its errors know the file and line.

## Steps

### 1. Skeleton

Build: repo layout, module manifest, `build.ps1`, CI, a test file with one case per error code that compares the code it gets.

Done when: an empty module imports on 5.1 and 7, and CI runs on Windows, Linux and macOS.

### 2. Reading and errors

Build: `Errors.ps1`, `Reader.ps1`.

Done when: every example file parses into a tree, and PSD100–PSD107 pass.

### 3. Writing

Build: `Writer.ps1`, `ConvertTo-Psd`, `Export-Psd`, `ConvertFrom-Psd` without grammar yet.

Done when: objects round-trip, including empty lists, single-item lists and `$null`, and PSD600–PSD605 pass.

### 4. Paths and keys

Build: `Path.ps1` using the path part of the parser, `Get-PsdValue`, `Set-PsdValue`, `Remove-PsdValue`, `Test-PsdKey`, `Get-PsdMissingKey`, `Assert-PsdKey`.

Done when: dotted, quoted and indexed paths work in every command.

### 5. References in one file

Build: `Grammar.ps1`, `Resolver.ps1`, `Filters.ps1`, the limits.

Done when: every example in `filters.md` gives the listed result, PSD300–PSD312 and PSD700 pass, and the doubling attack stops at the limit.

### 6. Merging and including

Build: `Loader.ps1`, `Merger.ps1`, operators, namespaces, `Merge-Psd`.

Done when: PSD200–PSD212 pass, and `this::`, late binding and included documents behave as in `DESIGN.md` section 6.

### 7. Conditions

Build: `Conditions.ps1`, `Import-Psd`, `Test-Psd`, `Get-PsdError`.

Done when: PSD400–PSD403 pass, and **importing `examples/everything/app.psd1` equals `examples/everything/result.psd1`**, and the same for `examples/config/last.psd1`. These are the main acceptance tests. Both results were worked out by hand, so a difference means either the code or the example is wrong, and I'll check which.

### 8. Schema

Build: `Schema.ps1`, `Test-PsdSchema`, `Add-PsdDefault`, `New-PsdSchema`.

Done when: PSD500–PSD515 pass except PSD512, and `result.psd1` passes `app.schema.psd1`.

### 9. Generated types

Build: `TypeGen.ps1`, `New-PsdType`.

Done when: output for `examples/config/app.schema.psd1` matches `examples/typed/App.Types.psm1`, the completion table in `DESIGN.md` section 11 holds using `TabExpansion2`, and PSD512 passes.

### 10. Editing and debugging

Build: `Update-Psd`, `Format-Psd`, `Compare-Psd`, `Get-PsdProvenance`, `Resolve-PsdReference`.

Done when: a file with comments keeps them through both editing commands, PSD606 and PSD607 pass, and the outputs in `examples/usage.ps1` match.

### 11. Finish

Build: comment-based help for every command, `README.md`, `install.ps1`, packaging.

Done when: `build.ps1 -Task Package` gives a zip, installing from it works on 5.1 and 7 in a clean session, and a repo using the `psdutil` branch as a submodule can import the module.

Publishing to the PowerShell Gallery happens only when you say so.

## Where it can go wrong

- **Speed on big files.** Walking an 830KB file took 0.4–0.8 seconds in plain PowerShell *(tested)*, so a file near the 100MB limit would take minutes. Fine for normal configs. If it becomes a problem, the reader is the first thing to optimise.
- **`Format-Psd`.** Moving code around while keeping comments in the right place is the hardest part of the module, which is why it's near the end.
- **`Resolve-PsdReference`.** Needs tracing inside the resolver. It's added last so it can't complicate the core.
