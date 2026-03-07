# NeoJJ: Neogit → jj Port Plan

Hard fork of Neogit to create a Magit-style Neovim UI for jj (Jujutsu VCS).

## Status Key

- [ ] Not started
- [~] In progress
- [x] Complete

---

## Phase 0: Mechanical Rename (neogit → neojj)

- [x] Rename `lua/neogit/` → `lua/neojj/`
- [x] Rename `plugin/neogit.lua` → `plugin/neojj.lua`
- [x] Replace all `require("neogit` → `require("neojj`
- [x] Rename user commands: `:Neogit` → `:NeoJJ`, `:NeogitResetState` → `:NeoJJResetState`, etc.
- [x] Rename highlights: `Neogit*` → `NeoJJ*`
- [x] Rename autocmd groups, buffer names, config keys
- [x] Rename internal variable references
- [x] Update doc files
- [x] Verify plugin still loads and opens (as a git plugin with new names)

---

## Phase 1: Core Infrastructure

Replace git internals with jj equivalents.

### CLI Builder (`lib/jj/cli.lua`)
- [x] Create jj fluent CLI builder (replacing git CLI builder)
- [x] Commands: `status`, `log`, `diff`, `show`, `describe`, `new`, `commit`, `squash`, `split`, `bookmark`, `git push`, `git fetch`, `rebase`, `abandon`, `restore`, `resolve`, `undo`, `op log`
- [x] Use `--no-pager`, `--color=never` for programmatic use
- [x] Use `-T 'json(self)'` template for machine-readable output where possible

### Repository State (`lib/jj/repository.lua`)
- [x] Define `NeoJJRepoState`:
  - `head`: current change (change_id, commit_id, description, empty, conflict)
  - `parent`: parent change (change_id, commit_id, description, bookmarks[])
  - `files`: modified files in working-copy change (single flat list, no staged/unstaged)
  - `conflicts`: files with first-class conflict status
  - `recent`: recent changes (change_id primary, commit_id secondary)
  - `bookmarks`: local and remote bookmarks
- [x] Populate state from `jj status`, `jj log -T 'json(self)'`, `jj bookmark list`

### Status Parsing (`lib/jj/status.lua`)
- [x] Parse `jj status` output for modified/added/deleted files
- [x] Parse `jj diff --summary` for file-level change info
- [x] No index/staging concepts

### Log Parsing (`lib/jj/log.lua`)
- [x] Parse `jj log` with JSON templates
- [x] Change ID as primary identifier, commit ID secondary
- [x] Track: change_id, commit_id, description, author, bookmarks, empty, conflict, immutable

---

## Phase 2: Status Buffer

### Status UI (`buffers/status/ui.lua`)
- [x] Section 1: Current change (change ID short, description, parent info with bookmarks)
- [x] Section 2: Modified files (single flat list)
- [x] Section 3: Conflicts (shown when conflicts exist)
- [x] Section 4: Recent changes (log with change IDs, descriptions, bookmarks, conflict/empty markers)
- [x] Section 5: Bookmarks (local and remote)

### Status Actions (`buffers/status/actions.lua`)
- [x] Remove: stage, unstage
- [x] Keep: fold/unfold, navigate sections, open file in split/tab/vsplit, refresh, close
- [x] Adapt: "Discard file" → `jj restore <path>`
- [x] Adapt: Diff viewing → `jj diff` for current change
- [x] Add: describe (edit current change description)

### Diff Display
- [x] Use `jj diff --git` for git-compatible diff format
- [x] Per-file diffs loaded lazily (same architecture as Neogit)

---

## Phase 3: Basic Actions

- [x] `jj describe` — edit change description (via editor buffer)
- [x] `jj new` — create new change (on top of current, or specified parent)
- [x] `jj squash` — move diff from current into parent
- [x] `jj abandon` — abandon current change
- [x] `jj restore <path>` — discard file changes
- [x] Diff viewing for files in status buffer

---

## Phase 4: Core Popups

### Commit Popup
- [x] `jj commit` (finish change & start new)
- [x] `jj describe` (edit message)
- [x] Options: message, reset-author, etc.

### Change Popup (new, jj-specific)
- [x] `jj new` (new change on top of current)
- [x] `jj new <rev>` (new change on specified parent)
- [x] `jj new @ A` (merge — multiple parents)
- [x] `--insert-before`, `--insert-after` options

### Squash Popup
- [x] `jj squash` (into parent)
- [x] `jj squash --into <rev>` (into arbitrary ancestor)
- [x] `jj squash -i` (interactive)

### Bookmark Popup
- [x] `jj bookmark create <name> [-r <rev>]`
- [x] `jj bookmark move <name> --to <rev>`
- [x] `jj bookmark delete <name>`
- [x] `jj bookmark track <name>@<remote>`
- [x] `jj bookmark forget <name>`
- [x] `jj bookmark list`

### Push Popup
- [x] `jj git push --bookmark <name>`
- [x] `jj git push --change <rev>`
- [x] `jj git push --all`
- [x] `--remote` option

### Fetch Popup
- [x] `jj git fetch`
- [x] `--remote`, `--all-remotes` options

---

## Phase 5: Views

### Log View (`buffers/log_view/`)
- [x] Show change IDs as primary, commit IDs secondary
- [x] Support revset filtering (`-r` option)
- [x] Graph display with change IDs
- [x] Pagination for large logs

### Diff View (`buffers/diff/`)
- [x] Parse `jj diff --git` output
- [x] Mostly unchanged from Neogit architecture

### Operations View (new)
- [x] Browse `jj op log`
- [x] Select operations to restore/revert
- [x] `jj undo` action

### Editor Buffer (`buffers/editor/`)
- [x] Adapt for `jj describe` message editing

---

## Phase 6: Remaining Popups

### Rebase Popup
- [x] `jj rebase -s <source> -d <dest>`
- [x] `jj rebase -b <bookmark> -d <dest>`
- [x] `jj rebase -r <rev> --before/--after <target>`

### Split Popup
- [x] `jj split` (interactive, split working copy)
- [x] `jj split -r <rev>` (split arbitrary change)

### Resolve Popup
- [x] `jj resolve` (launch merge tool for conflicted files)
- [x] File selection for multi-file conflicts

### Other Popups
- [x] Remote: `jj git remote` (add, remove, rename, list)
- [x] Yank: copy change ID / commit ID to clipboard
- [x] Diff: `jj diff` format options (--summary, --stat, --git, --color-words)
- [x] Log: `jj log` filtering (-r revset, -p patch, --no-graph)
- [x] Help: adapted for jj keybindings

---

## Phase 7: Polish

- [ ] Clean up config.lua (remove git-specific options, add jj-specific ones)
- [ ] Update all highlights and signs
- [ ] Write documentation (doc/ help files)
- [ ] Remove dead code (git-only modules: stash, bisect, cherry_pick, index, worktree, etc.)
- [ ] Update README

---

## Removed from Neogit (no jj equivalent)

- Stash popup/view (replaced by `jj new @-` workflow)
- Cherry-pick popup (replaced by `jj duplicate`)
- Reset popup (replaced by `jj restore` / `jj abandon`)
- Merge popup (subsumed by `jj new @ A` in change popup)
- Bisect popup/view (jj has no bisect)
- Branch config / remote config popups (git-specific)
- Rebase editor buffer (no interactive rebase todo in jj)
- Stash list view, reflog view (replaced by operations view)
- Index/staging concepts throughout

---

## Key jj Concepts Reference

- **Change ID**: Immutable identifier for a change (stays constant as content evolves)
- **Commit ID**: SHA hash that changes on every rewrite
- **`@`**: Working-copy change (revset symbol)
- **`@-`**: Parent of working copy
- **No staging area**: All file changes are part of the current change automatically
- **Auto-snapshotting**: Working copy is snapshotted on every jj command
- **First-class conflicts**: Conflicts stored in commits, don't block operations
- **Bookmarks**: Named pointers to commits (replaces git branches)
- **Operations log**: Every repo operation is recorded, supports undo/restore
- **Revsets**: Functional language for selecting revision sets
- **Templates**: `jj log -T 'json(self)' --no-graph` for machine-readable output
