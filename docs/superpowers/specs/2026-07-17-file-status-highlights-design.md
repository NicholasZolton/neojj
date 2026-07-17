# File Status Highlights

## Goal

Match Neogit's status-file coloring in NeoJJ. The status label for each changed file should use the existing highlight group for that file state, while the filename should retain its current text highlight.

This change addresses the file-state portion of issue 30. Bookmark styling remains out of scope.

## Design

The status file renderer will select an existing `NeojjChange*` highlight group from the Jujutsu file mode:

| Mode | Highlight group |
| --- | --- |
| `M` | `NeojjChangeModified` |
| `A` | `NeojjChangeAdded` |
| `N` | `NeojjChangeNewFile` |
| `D` | `NeojjChangeDeleted` |
| `R` | `NeojjChangeRenamed` |
| `C` | `NeojjChangeCopied` |
| `U`, `T` | `NeojjChangeUpdated` |
| `DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU` | `NeojjChangeUnmerged` |

Unknown modes will use `NeojjFileMode`, preserving the current behavior as a fallback.

The renderer will apply the selected group only to the configured mode label, such as `modified` or `deleted`. It will not add a highlight to the filename. NeoJJ will derive its red palette from `ErrorMsg`, matching current Neogit and avoiding the reversed foreground/background values that some colorschemes assign to `Error`. Colorscheme overrides for `NeojjChangeModified`, `NeojjChangeAdded`, and the other state groups will continue to control the colors.

## Testing

A focused status UI spec will render representative file modes. It will assert that each mode label uses its matching `NeojjChange*` group and that each filename has no explicit highlight. A palette spec will assert that deleted-file red derives from `ErrorMsg`, as it does in Neogit. The tests will exercise the status renderer and highlight setup rather than separate exported helpers.

The full test suite and Lua formatting checks will run after implementation.
