# Remove Git Dependencies from Consumer Code

**Date:** 2026-03-12
**Status:** Draft

## Goal

Eliminate all `require("neojj.lib.git")` usage from consumer code outside of `lib/git/` and the diffview/codediff integrations. After this work, the only files that import `lib/git` are:

- `lib/git/*.lua` (internal to the git library)
- `integrations/diffview.lua` (explicitly kept for git-colocated mode)
- `integrations/codediff.lua` (explicitly kept for git-colocated mode)

## Non-goals

- Removing or refactoring `lib/git/` itself — it stays for diffview/codediff.
- Making diffview/codediff work without git colocated mode.
- Adding new features or UI changes beyond what's needed for the rewiring.

## Design principle

Each capability lives in one place in the jj layer. Consumers call into that single home. No duplicated logic, no shotgun surgery if the jj API changes later.

## New jj capabilities

### 1. `lib/jj/config.lua` (new file)

Wraps `jj config` for reading and writing repo-scoped configuration. Must return `ConfigEntry` objects to match the contract expected by the popup system (`.value`, `:type()`, `:is_set()`, `:is_unset()`, `:read()`, `:update()`).

```lua
local M = {}

---@class JjConfigEntry
---@field value string
---@field name string
local ConfigEntry = {}
ConfigEntry.__index = ConfigEntry

function ConfigEntry.new(name, value)
  return setmetatable({ name = name, value = value or "" }, ConfigEntry)
end

function ConfigEntry:type()
  if self.value == "true" or self.value == "false" then return "boolean"
  elseif tonumber(self.value) then return "number"
  else return "string" end
end

function ConfigEntry:is_set() return self.value ~= "" end
function ConfigEntry:is_unset() return not self:is_set() end

function ConfigEntry:read()
  if self:is_unset() then return nil end
  if self:type() == "boolean" then return self.value == "true"
  elseif self:type() == "number" then return tonumber(self.value)
  else return self.value end
end

function ConfigEntry:update(value)
  if not value or value == "" then
    if self:is_set() then M.unset(self.name) end
  else
    M.set(self.name, value)
  end
end

---@param key string e.g., "neojj.popup.push.force"
---@return JjConfigEntry
function M.get(key) end

---@param key string
---@param value string
function M.set(key, value) end

---@param key string
function M.unset(key) end

return M
```

Implementation uses `define_command` entries in `cli.lua` (see capability 2 below) to stay consistent with the builder pattern:
- `get`: `jj.cli.config_get.args(key).call(...)` — returns `ConfigEntry.new(key, stdout[1])`
- `set`: `jj.cli.config_set.repo.args(key, value).call(...)`
- `unset`: `jj.cli.config_unset.repo.args(key).call(...)` — guarded with `is_set()` check first

**Used by:** `lib/popup/builder.lua`, `lib/popup/init.lua`

### 2. New CLI command definitions in `lib/jj/cli.lua`

Add these command definitions:

```lua
-- jj file show
define_command("file show", {
  options = {
    revision = "-r",
  },
})

-- jj config get
define_command("config get", {})

-- jj config set
define_command("config set", {
  flags = {
    repo = "--repo",
    user = "--user",
  },
})

-- jj config unset
define_command("config unset", {
  flags = {
    repo = "--repo",
    user = "--user",
  },
})
```

These enable:
- `jj.cli.file_show.revision(rev).args(path).call(...)` — retrieve file contents at a revision
- `jj.cli.config_get.args(key).call(...)` — read config
- `jj.cli.config_set.repo.args(key, value).call(...)` — write repo-scoped config
- `jj.cli.config_unset.repo.args(key).call(...)` — unset repo-scoped config

**Used by:** `lib/jump.lua`, `lib/jj/config.lua`

### 3. `Repo:relpath(path)` method on `lib/jj/repository.lua`

Pure path math — computes a file path relative to the workspace root. No subprocess call.

```lua
---@param absolute_path string
---@return string|nil relative path, or nil if path is outside the workspace
function Repo:relpath(absolute_path) end
```

Implementation: strips `self.worktree_root .. "/"` prefix from the path. Returns `""` if path equals worktree root exactly. Returns nil if the path doesn't start with the workspace root.

**Used by:** `autocmds.lua`

### 4. Command history — no new code needed

The shared `runner.lua` module already tracks command history in `runner.history` for all commands (both git and jj) dispatched through `runner.call()`. The jj CLI's `M._call()` already calls `runner.call()`, so jj commands are already recorded.

The `git_command_history` buffer currently reads `Git.cli.history`, which is just an alias for `runner.history` (see `lib/git/cli.lua:1302`). The renamed `command_history` buffer will read `runner.history` directly.

**No changes to `lib/jj/cli.lua` are needed for history.**

## Consumer rewiring

### `autocmds.lua`

**Before:**
```lua
local git = require("neojj.lib.git")
-- ...
local path = git.files.relpath_from_repository(o.file)
```

**After:**
```lua
local jj = require("neojj.lib.jj")
-- ...
local path = jj.repo:relpath(o.file)
```

### `lib/jump.lua`

Two usages:

**Line 155 — worktree root:**
```lua
-- Before:
local absolute_path = vim.fs.joinpath(git.repo.worktree_root, path)
-- After:
local absolute_path = vim.fs.joinpath(jj.repo.worktree_root, path)
```

**Line 225 — file contents at revision:**
```lua
-- Before:
git.cli.show.file(path, target_commit).call { hidden = true, trim = false, ignore_error = true }
-- After:
jj.cli.file_show.revision(target_commit).args(path).call { hidden = true, trim = false }
```

Note: `jj file show` outputs raw file content (no diff header), which is exactly what this call site needs.

### `lib/popup/builder.lua`

**Before:**
```lua
local git = require("neojj.lib.git")
-- ...
local entry = git.config.get(name)
```

**After:**
```lua
local jj_config = require("neojj.lib.jj.config")
-- ...
local entry = jj_config.get(name)
```

### `lib/popup/init.lua`

Three usages:

**Lines 267-280 — config set/get:**
```lua
-- Before:
git.config.set(config.name, config.value)
local c_value = git.config.get(var.name)
-- After:
jj_config.set(config.name, config.value)
local c_value = jj_config.get(var.name)
```

**Line 430 — branch name highlight:**
```lua
-- Before:
vim.fn.matchadd("NeojjPopupBranchName", git.repo.state.head.branch, 100)
-- After:
local bookmarks = jj.repo.state.head.bookmarks
if #bookmarks > 0 then
  for _, bm in ipairs(bookmarks) do
    vim.fn.matchadd("NeojjPopupBranchName", bm, 100)
  end
end
```

### `buffers/fuzzy_finder.lua`

**Before:**
```lua
local git = require("neojj.lib.git")
-- ...
local ok, result = pcall(git.log.decorate, oid)
```

**After:** Remove the git import and the OID decoration block entirely. jj log entries already carry bookmark information — commit OID decoration is a git-ism that doesn't apply.

### `buffers/git_command_history.lua` → `buffers/command_history.lua`

Rename the file. Change:
```lua
-- Before:
local Git = require("neojj.lib.git")
-- references to Git.cli.history
-- After:
local jj_cli = require("neojj.lib.jj.cli")
-- references to jj_cli.history
```

Update the `command_mask` for display stripping. The git mask strips `--no-pager --literal-pathspecs --no-optional-locks ...`; the jj equivalent strips `--no-pager --color=never` (and `--ignore-working-copy` for readonly commands).

Rename the buffer name and filetype from `NeojjGitCommandHistory` to `NeojjCommandHistory`. This is a **breaking change** for users with filetype-specific autocmds targeting the old name.

Update the 3 files that reference the old module path:
- `buffers/status/actions.lua:359` — `require("neojj.buffers.git_command_history")` → `require("neojj.buffers.command_history")`
- `lib/ui/helpers.lua:9` — same change
- `popups/help/actions.lua:41` — same change

### `lib.lua`

Remove the git export:
```lua
-- Before:
git = require("neojj.lib.git"), -- kept for reference during migration
-- After:
-- (line removed)
```

## Testing

Tests use the existing `describe`/`it` pattern with busted (see `tests/specs/`). New test files:

- `tests/specs/neojj/lib/jj/config_spec.lua`
- `tests/specs/neojj/lib/jj/repository_spec.lua` (new, for `relpath`)

Existing test files to extend:

- `tests/specs/neojj/lib/jj/cli_spec.lua` (add cases for new commands and history)

### `lib/jj/config.lua` (`tests/specs/neojj/lib/jj/config_spec.lua`)

Unit tests for the `ConfigEntry` class and the config module:

- `ConfigEntry.new(name, value)` — creates entry with correct fields
- `ConfigEntry:type()` — returns `"boolean"` for `"true"`/`"false"`, `"number"` for numeric strings, `"string"` otherwise
- `ConfigEntry:is_set()` / `:is_unset()` — true/false based on empty string value
- `ConfigEntry:read()` — returns typed value (`true`/`false` for booleans, number for numeric, string otherwise, nil if unset)
- `ConfigEntry:update(value)` — calls `M.set` for non-empty values, `M.unset` for empty/nil
- `M.get(key)` — returns `ConfigEntry` with value from `jj config get`, returns unset entry on missing key
- `M.set(key, value)` — calls `jj config set --repo`
- `M.unset(key)` — calls `jj config unset --repo`, no-ops if already unset

### `lib/jj/repository.lua` — `Repo:relpath()` (`tests/specs/neojj/lib/jj/repository_spec.lua`)

- Returns relative path when given absolute path inside workspace root
- Returns `""` when path equals workspace root exactly
- Returns `nil` when path is outside workspace root
- Handles trailing slashes correctly

### `lib/jj/cli.lua` — new commands (extend `tests/specs/neojj/lib/jj/cli_spec.lua`)

- `file show` command builds correct args: `jj --no-pager --color=never --ignore-working-copy file show -r <rev> <path>`
- `config get` command builds correct args: `jj --no-pager --color=never config get <key>`
- `config set` with `.repo` flag builds: `jj --no-pager --color=never config set --repo <key> <value>`
- `config unset` with `.repo` flag builds: `jj --no-pager --color=never config unset --repo <key>`

## Migration notes

- **Config key namespace:** Popup config values currently stored under git config keys (e.g., `push.force`) will need a new namespace. Suggest `neojj.popup.<popup-name>.<key>` to avoid collision with jj's own config. Existing saved values in `.git/config` won't migrate — popups will start with defaults, which is acceptable.

- **Buffer rename:** `NeojjGitCommandHistory` filetype/buffer name becomes `NeojjCommandHistory`. Users with filetype autocmds targeting the old name will need to update them.

- **Bookmark highlight is a visual behavior change:** The git code highlighted a single branch name in popup headers. The jj version highlights all bookmarks on the working copy change, which may be multiple. This changes the visual appearance when a change has multiple bookmarks.

- **Testing:** The test mock at `tests/mocks/commit_select_buffer.lua` imports git — check if it's used in any active tests and update or remove accordingly. The `tests/README.md` references `neojj.lib.git.cli` in documentation — update to avoid stale references.

## Files changed summary

| File | Change type |
|---|---|
| `lib/jj/config.lua` | **New** — ConfigEntry-compatible config wrapper |
| `lib/jj/cli.lua` | Add `file show`, `config get/set/unset` commands |
| `lib/jj/repository.lua` | Add `Repo:relpath()` method |
| `autocmds.lua` | Rewire git → jj |
| `lib/jump.lua` | Rewire git → jj |
| `lib/popup/builder.lua` | Rewire git.config → jj.config |
| `lib/popup/init.lua` | Rewire git.config → jj.config, bookmarks instead of branch |
| `buffers/fuzzy_finder.lua` | Remove git import and OID decoration |
| `buffers/git_command_history.lua` → `buffers/command_history.lua` | Rename + rewire + update command_mask |
| `buffers/status/actions.lua` | Update require path for command_history |
| `lib/ui/helpers.lua` | Update require path for command_history |
| `popups/help/actions.lua` | Update require path for command_history |
| `lib/ui/init.lua` | Remove commented-out git reference |
| `lib.lua` | Remove git export |
| `tests/mocks/commit_select_buffer.lua` | Check and update |
| `tests/README.md` | Update stale git.cli reference |
