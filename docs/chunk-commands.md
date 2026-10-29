# Chunk-Scoped Status Commands

## User Interface

Expand a changed file with `<Tab>`. All four commands work in normal and visual mode:

| Default | Mapping | Operation |
| --- | --- | --- |
| `x` | `Discard` | Discard selected changes after confirmation |
| `S` | `SplitSelection` | Split selected changes into a commit |
| `C` | `CommitSelection` | Commit selected changes |
| `gs` | `SquashSelection` | Move selected changes into the parent |

The existing commit (`c`), squash (`s`) and undo (`u`) popups remain unchanged.

Help (`?`) separates **Revisions (cursor)**, **Bookmarks (cursor)**,
**Selected changes (files)** and **Navigation**. These are scope labels, not
additional selection modes: revision/bookmark actions remain normal-mode
commands, while chunk commands accept cursor or visual selection. On a recent
change, `x` appears as **Abandon change** under revisions; on a local bookmark,
it appears as **Delete bookmark** or **Restore bookmark from origin**. On a
remote bookmark, `F` reads **Track remote bookmark** and unsupported `x` deletion
is omitted. Other groups remain visible as a keybinding reference.

Normal mode selects the complete hunk under the cursor, including when the
cursor is on a context line. A file header selects the entire file. The files
section header selects all changed files. Folded file/hunk headers work without
expanding them first.

Visual mode selects displayed changed rows across multiple hunks and files.
Including a hunk header selects that whole hunk; including a file header selects
that whole file. Reverse selections work. Context-only selections do not run a
command. Blockwise selection is rejected rather than silently widened.

As in Neogit, selecting `+` and `-` rows is literal. Selecting only an added row
in a replacement adds that row while retaining unselected old rows. Selecting
only a removed row removes that row without adding its replacement. For a
complete replacement, select both sides. No line-pair matching is inferred.

Commit and split use the existing NeoJJ description editor, including multiline
messages and cancellation. Split retains native JJ behavior when editing both
commit descriptions. The editor does not show the whole working-copy diff as a
misleading preview of the selected changes. Squash preserves the destination
commit's description, including when the source becomes empty.

Unselected changes remain in the working copy. `jj commit` retains bookmarks on
the selected commit; `jj split` uses native bookmark-forwarding behavior. There
is no staging area. Use `u` or `jj undo` to undo the completed operation.

Mappings are customizable through `mappings.status` using the names in the table.
Successful commit, split and squash actions emit `NeojjCommitComplete`,
`NeojjSplitComplete` and `NeojjSquashComplete`, respectively.

## Transaction Adapter

1. Capture selections from actual rendered component positions, not cached hunk
   screen ranges. Folding another hunk cannot redirect the command.
2. Snapshot and compare the working-copy commit ID with the displayed revision.
   Reject stale selections and refresh status instead of guessing.
3. Whole-file-only selections use native JJ filesets. Filesets are quoted,
   exact, workspace-relative paths, not shell commands or glob patterns.
4. Chunk selections configure a temporary `neojj-chunks` external diff editor.
   No global/repository JJ configuration is modified.
5. Launch a clean headless instance of the same Neovim binary. The helper checks
   the working-copy ID again and validates all cached hunk ranges and contents
   against both JJ temporary trees.
6. Construct the selected tree for split/commit/squash, or its complement for
   discard. Chunk discard uses `jj diffedit -r @` so all operations share the
   same parent-to-working-copy orientation.
7. Validate every selected file before writing anything. Modify only JJ's
   temporary right-hand tree. JJ snapshots the result, applies the transaction
   and rebases descendants. Helper/editor failure aborts the transaction.
8. Remove private temporary metadata/configuration and refresh status on both
   success and failure. JJ's operation log provides recovery.

The adapter never temporarily patches real working-copy files. Raw byte lines
retain CRLF and missing final newlines. Added/deleted files retain the distinction
between empty and absent files. Existing executable mode is preserved.

## Boundaries

Tested with JJ 0.41 and Neovim 0.12. The plugin's existing JJ minimum is unchanged;
older versions may lack options required by chunk commands.

- Binary files, symlinks and executable-bit changes require whole-file selection.
- Mixed whole-file/chunk operations require regular files throughout.
- Chunk operations reject conflicted source/parent revisions. Whole-file commands
  retain native JJ behavior; use native tools for more specific conflict handling.
- Renamed/copied chunks are unsupported. Whole-file renames/copies cannot be
  mixed with chunks. Rename/copy selection needs separate source/destination
  paths; when status
  does not provide them, use native JJ commands instead.
- A partial selection that would concatenate unterminated lines aborts. Select
  the complete EOF replacement instead.
- Undo is JJ operation undo, not a synthetic staging index or per-line undo stack.

## Verification

Specs cover the byte-preserving selection engine, cursor and visual selection,
folded hunks, CLI options, and real temporary JJ workspaces. Integration coverage
includes all four operations, partial additions/deletions, multiple files,
fileset metacharacters, CRLF, missing final newlines, executable mode, binary
whole-file restore, symlink rejection/native restore, stale selections,
transaction failures, description-editor
cancellation and undo recovery. No tests contact a remote service.
