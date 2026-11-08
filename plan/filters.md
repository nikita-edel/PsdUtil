# Filters

A filter changes a value inside a reference. It goes after `|`, and you can chain them:

```powershell
Slug = '!<Name | lower | replace(" ", "-")>'
```

This is the full list. You can't add your own, so a filter can never loop or hang.

## Text

```powershell
# A = '  Hello World  '

'!<A | lower>'                       # makes it lowercase        '  hello world  '
'!<A | upper>'                       # makes it uppercase        '  HELLO WORLD  '
'!<A | trim>'                        # removes spaces at the ends 'Hello World'
'!<A | replace("World", "There")>'   # replaces every match      '  Hello There  '
'!<A | trim | split(" ")>'           # cuts into a list          @('Hello', 'World')
```

## Lists

```powershell
# L = @('c', 'a', 'c', 'b')

'!<L | join("-")>'                   # glues into text           'c-a-c-b'
'!<L | first>'                       # the first item            'c'
'!<L | last>'                        # the last item             'b'
'!<L | sort>'                        # sorts the items           @('a', 'b', 'c', 'c')
'!<L | unique>'                      # drops repeats, in order   @('c', 'a', 'b')
'!<L | count>'                       # how many items            4
```

## Maps

```powershell
# M = @{ A = 1; B = 2 }

'!<M | keys>'                        # the keys, as a list       @('A', 'B')
'!<M | values>'                      # the values, as a list     @(1, 2)
```

## Rules

- A filter's arguments can be text, a number, or another key: `replace("World", Words.Who)`.
- `$null` stays `$null`: `!<?Missing | upper>` gives `$null`.
- `first` and `last` on an empty list give `$null`.
- `replace` and `split` use plain text, not regex.
- `replace` and `split` match case exactly. `sort` and `unique` ignore case.
- An unknown filter is `PSD311`. The wrong kind of value or wrong arguments is `PSD312`.

Adding to or removing from a list isn't a filter. That's the merge operators: `+=`, `=+`, `|=`, `-=`, `:=`.
