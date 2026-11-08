# PsdUtil

## General Utility

* Adds a way to verify that certain keys are present in a map
  - ensure a one or more keys are present (list of strings)

- Other utility that the classic PS data one public module has<br>
(at least the most usefull ones) (there is not much there)

- adds a way to convert any object into a psd (text, file)

- adds a way to define a schema, that define the structure of the psd
  - (types, kinds, similar to the json way), and helpfull messages generated, + optional description inside the schema
  - think of other usefull things for the schema

- function to just test the validity
- maybe even generate types that i can do something `using module ...` for auto completion
  - that would be used in another ps1 file that at the end returns a psd file


## Custom Grammar/Parsing

- adds a way of referencing keys inside its own object
  - even for submaps
- adds a way of modifying keys inside its own object (maps, lists, values, and so on)
- keys for own name, current directory
- conditions: modify content on condition

------
- adds way of merging n psd (ordered)
- adds a way to "include" n psd (to be able to 'access' its keys) (ordered)<br>
(same as merging, but the result is non merged, but only the called keys get replaced
  - custom grammar for: replacing key/merging key
  - merging only certain keys
  - calling keys from the other ones e.g. firstone::Options

- keys that expand to the latest chained psd (non-own name etc) (not its own)(evaluate after merging)
- typos in the reference: add a way to handle: unknown keys referenced: {we need to think on how to do this}
- we also need the best possible grammar for the reference, my thought was `!<...>`

- fully cover all possible errors: e.g. detect recursion (cover all edgecases)
