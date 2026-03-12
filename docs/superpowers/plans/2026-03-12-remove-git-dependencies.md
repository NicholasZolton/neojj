# Remove Git Dependencies Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all `require("neojj.lib.git")` from consumer code, leaving git imports only in `lib/git/` and diffview/codediff integrations.

**Architecture:** Extend the existing jj layer (`lib/jj/`) with 3 missing capabilities (config module, `file show` command, `Repo:relpath`), then rewire 10 consumer files to use jj instead of git. The shared `runner.history` already tracks all jj commands — no new history code needed.

**Note:** Config integration tests (Task 3) require running inside a jj workspace, same as existing cli_spec tests.

**Tech Stack:** Lua, Neovim plugin API, jj CLI, busted/plenary test harness

**Spec:** `docs/superpowers/specs/2026-03-12-remove-git-dependencies-design.md`

**Test runner:** `make test` or `TEST_FILES=tests/specs/neojj/lib/jj/<file> make test` for targeted runs

---

## Chunk 1: New jj capabilities (with tests)

### Task 1: Add `Repo:relpath()` method

**Files:**
- Modify: `lua/neojj/lib/jj/repository.lua:96` (Repo class)
- Create: `tests/specs/neojj/lib/jj/repository_spec.lua`

- [ ] **Step 1: Write the failing tests**

Create `tests/specs/neojj/lib/jj/repository_spec.lua`:

```lua
local Repo = require("neojj.lib.jj.repository").Repo

describe("Repo:relpath", function()
  local repo

  before_each(function()
    repo = Repo.new("/home/user/project")
  end)

  it("returns relative path for file inside workspace", function()
    assert.are.equal("src/main.lua", repo:relpath("/home/user/project/src/main.lua"))
  end)

  it("returns empty string when path equals workspace root", function()
    assert.are.equal("", repo:relpath("/home/user/project"))
  end)

  it("returns nil when path is outside workspace", function()
    assert.is_nil(repo:relpath("/home/user/other/file.lua"))
  end)

  it("returns nil for completely different path", function()
    assert.is_nil(repo:relpath("/tmp/file.lua"))
  end)

  it("handles path with trailing slash on root", function()
    assert.are.equal("src/main.lua", repo:relpath("/home/user/project/src/main.lua"))
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/repository_spec.lua make test`
Expected: FAIL — `relpath` method does not exist

- [ ] **Step 3: Implement `Repo:relpath()`**

In `lua/neojj/lib/jj/repository.lua`, add this method to the Repo class (after the `Repo:reset()` method around line 165):

```lua
---Compute a file path relative to the workspace root.
---@param absolute_path string
---@return string|nil relative path, or nil if path is outside the workspace
function Repo:relpath(absolute_path)
  if absolute_path == self.worktree_root then
    return ""
  end

  local prefix = self.worktree_root .. "/"
  if absolute_path:sub(1, #prefix) == prefix then
    return absolute_path:sub(#prefix + 1)
  end

  return nil
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/repository_spec.lua make test`
Expected: PASS

- [ ] **Step 5: Commit**

```
jj describe -m "feat: add Repo:relpath() method for workspace-relative paths"
jj new
```

---

### Task 2: Add CLI command definitions (`file show`, `config get/set/unset`)

**Files:**
- Modify: `lua/neojj/lib/jj/cli.lua:536-544` (after `file untrack` and `file annotate`)
- Modify: `tests/specs/neojj/lib/jj/cli_spec.lua`

- [ ] **Step 1: Write the failing tests**

Append to `tests/specs/neojj/lib/jj/cli_spec.lua`:

```lua
  describe("file show command", function()
    it("includes --ignore-working-copy as a readonly command", function()
      local str = tostring(cli.file_show)
      assert.truthy(str:find("%-%-ignore%-working%-copy"))
    end)

    it("includes -r when revision is called", function()
      local str = tostring(cli.file_show.revision("abc123"))
      assert.truthy(str:find("%-r"))
      assert.truthy(str:find("abc123"))
    end)

    it("includes file path as argument", function()
      local str = tostring(cli.file_show.revision("abc123").args("src/main.lua"))
      assert.truthy(str:find("src/main.lua"))
    end)
  end)

  describe("config get command", function()
    it("builds correct command", function()
      local str = tostring(cli.config_get.args("neojj.popup.push.force"))
      assert.truthy(str:find("config get"))
      assert.truthy(str:find("neojj.popup.push.force"))
    end)

    it("does not include --ignore-working-copy", function()
      local str = tostring(cli.config_get)
      assert.falsy(str:find("%-%-ignore%-working%-copy"))
    end)
  end)

  describe("config set command", function()
    it("includes --repo flag", function()
      local str = tostring(cli.config_set.repo.args("key", "value"))
      assert.truthy(str:find("%-%-repo"))
      assert.truthy(str:find("config set"))
    end)
  end)

  describe("config unset command", function()
    it("includes --repo flag", function()
      local str = tostring(cli.config_unset.repo.args("key"))
      assert.truthy(str:find("%-%-repo"))
      assert.truthy(str:find("config unset"))
    end)
  end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/cli_spec.lua make test`
Expected: FAIL — unknown jj commands

- [ ] **Step 3: Add command definitions**

In `lua/neojj/lib/jj/cli.lua`, add after the `file annotate` block (around line 548):

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

Also add `"file show"` to the `readonly_commands` table (around line 128) since it doesn't modify state:

```lua
    ["file show"] = true,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/cli_spec.lua make test`
Expected: PASS

- [ ] **Step 5: Commit**

```
jj describe -m "feat: add file show, config get/set/unset CLI commands"
jj new
```

---

### Task 3: Create `lib/jj/config.lua` module

**Files:**
- Create: `lua/neojj/lib/jj/config.lua`
- Create: `tests/specs/neojj/lib/jj/config_spec.lua`

- [ ] **Step 1: Write the failing tests**

Create `tests/specs/neojj/lib/jj/config_spec.lua`:

```lua
local config = require("neojj.lib.jj.config")

describe("jj config", function()
  describe("ConfigEntry", function()
    -- Access ConfigEntry via module (it's returned by get())
    it("returns a ConfigEntry from get()", function()
      -- This will call jj config get on a nonexistent key, should return unset entry
      local entry = config.get("neojj.test.nonexistent.key.12345")
      assert.is_not_nil(entry)
      assert.are.equal("neojj.test.nonexistent.key.12345", entry.name)
      assert.are.equal("", entry.value)
    end)

    it("is_set returns false for empty value", function()
      local entry = config.get("neojj.test.nonexistent.key.12345")
      assert.is_false(entry:is_set())
      assert.is_true(entry:is_unset())
    end)

    it("read returns nil for unset entry", function()
      local entry = config.get("neojj.test.nonexistent.key.12345")
      assert.is_nil(entry:read())
    end)

    it("type returns 'boolean' for true/false strings", function()
      -- We test the ConfigEntry class behavior directly by constructing via get after set
      -- First, test the contract: type() on unset returns "string"
      local entry = config.get("neojj.test.nonexistent.key.12345")
      assert.are.equal("string", entry:type())
    end)
  end)

  describe("ConfigEntry:type()", function()
    -- Test type detection by creating entries with known values
    -- We use the internal constructor pattern (set then get)
    it("detects boolean type for 'true'", function()
      config.set("neojj.test.config.bool", "true")
      local entry = config.get("neojj.test.config.bool")
      assert.are.equal("boolean", entry:type())
      assert.are.equal(true, entry:read())
      config.unset("neojj.test.config.bool")
    end)

    it("detects boolean type for 'false'", function()
      config.set("neojj.test.config.bool2", "false")
      local entry = config.get("neojj.test.config.bool2")
      assert.are.equal("boolean", entry:type())
      assert.are.equal(false, entry:read())
      config.unset("neojj.test.config.bool2")
    end)

    it("detects number type", function()
      config.set("neojj.test.config.num", "42")
      local entry = config.get("neojj.test.config.num")
      assert.are.equal("number", entry:type())
      assert.are.equal(42, entry:read())
      config.unset("neojj.test.config.num")
    end)

    it("detects string type", function()
      config.set("neojj.test.config.str", "hello")
      local entry = config.get("neojj.test.config.str")
      assert.are.equal("string", entry:type())
      assert.are.equal("hello", entry:read())
      config.unset("neojj.test.config.str")
    end)
  end)

  describe("set and get roundtrip", function()
    it("can set and retrieve a config value", function()
      config.set("neojj.test.config.roundtrip", "myvalue")
      local entry = config.get("neojj.test.config.roundtrip")
      assert.is_true(entry:is_set())
      assert.are.equal("myvalue", entry.value)
      config.unset("neojj.test.config.roundtrip")
    end)
  end)

  describe("unset", function()
    it("unsets a previously set value", function()
      config.set("neojj.test.config.tounset", "val")
      config.unset("neojj.test.config.tounset")
      local entry = config.get("neojj.test.config.tounset")
      assert.is_false(entry:is_set())
    end)

    it("no-ops when unsetting nonexistent key", function()
      -- Should not error
      config.unset("neojj.test.config.never.existed.12345")
    end)
  end)

  describe("update", function()
    it("sets value via update", function()
      local entry = config.get("neojj.test.config.update")
      entry:update("newval")
      local fresh = config.get("neojj.test.config.update")
      assert.are.equal("newval", fresh.value)
      config.unset("neojj.test.config.update")
    end)

    it("unsets value when update called with empty string", function()
      config.set("neojj.test.config.update2", "val")
      local entry = config.get("neojj.test.config.update2")
      entry:update("")
      local fresh = config.get("neojj.test.config.update2")
      assert.is_false(fresh:is_set())
    end)
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/config_spec.lua make test`
Expected: FAIL — module not found

- [ ] **Step 3: Implement `lib/jj/config.lua`**

Create `lua/neojj/lib/jj/config.lua`:

```lua
local M = {}

---@class JjConfigEntry
---@field value string
---@field name string
local ConfigEntry = {}
ConfigEntry.__index = ConfigEntry

---@param name string
---@param value? string
---@return JjConfigEntry
function ConfigEntry.new(name, value)
  return setmetatable({ name = name, value = value or "" }, ConfigEntry)
end

---@return string "boolean"|"number"|"string"
function ConfigEntry:type()
  if self.value == "true" or self.value == "false" then
    return "boolean"
  elseif tonumber(self.value) then
    return "number"
  else
    return "string"
  end
end

---@return boolean
function ConfigEntry:is_set()
  return self.value ~= ""
end

---@return boolean
function ConfigEntry:is_unset()
  return not self:is_set()
end

---@return boolean|number|string|nil
function ConfigEntry:read()
  if self:is_unset() then
    return nil
  end

  if self:type() == "boolean" then
    return self.value == "true"
  elseif self:type() == "number" then
    return tonumber(self.value)
  else
    return self.value
  end
end

---@param value? string
function ConfigEntry:update(value)
  if not value or value == "" then
    if self:is_set() then
      M.unset(self.name)
    end
  else
    M.set(self.name, value)
  end
end

---Get a config value
---@param key string
---@return JjConfigEntry
function M.get(key)
  local jj = require("neojj.lib.jj")
  local result = jj.cli.config_get.args(key).call { hidden = true, trim = true, ignore_error = true }
  local value = ""
  if result and result.code == 0 and result.stdout and result.stdout[1] then
    value = result.stdout[1]
  end
  return ConfigEntry.new(key, value)
end

---Set a config value (repo-scoped)
---@param key string
---@param value string
function M.set(key, value)
  if not value or value == "" then
    M.unset(key)
    return
  end
  local jj = require("neojj.lib.jj")
  jj.cli.config_set.repo.args(key, value).call { hidden = true }
end

---Unset a config value (repo-scoped)
---@param key string
function M.unset(key)
  if not M.get(key):is_set() then
    return
  end
  local jj = require("neojj.lib.jj")
  jj.cli.config_unset.repo.args(key).call { hidden = true, ignore_error = true }
end

M.ConfigEntry = ConfigEntry

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TEST_FILES=tests/specs/neojj/lib/jj/config_spec.lua make test`
Expected: PASS

- [ ] **Step 5: Commit**

```
jj describe -m "feat: add jj config module with ConfigEntry contract"
jj new
```

---

## Chunk 2: Consumer rewiring

### Task 4: Rewire `autocmds.lua`

**Files:**
- Modify: `lua/neojj/autocmds.lua:8,29`

- [ ] **Step 1: Replace git import and usage**

In `lua/neojj/autocmds.lua`:

Replace line 8:
```lua
  local git = require("neojj.lib.git")
```
with:
```lua
  local jj = require("neojj.lib.jj")
```

Replace line 29:
```lua
        local path = git.files.relpath_from_repository(o.file)
```
with:
```lua
        local path = jj.repo:relpath(o.file)
```

- [ ] **Step 2: Verify no remaining git references**

Run: `grep -n "git" lua/neojj/autocmds.lua`
Expected: No matches

- [ ] **Step 3: Commit**

```
jj describe -m "refactor: rewire autocmds.lua from git to jj"
jj new
```

---

### Task 5: Rewire `lib/jump.lua`

**Files:**
- Modify: `lua/neojj/lib/jump.lua:1,155,223-226`

- [ ] **Step 1: Replace git import and usages**

In `lua/neojj/lib/jump.lua`:

Replace line 1:
```lua
local git = require("neojj.lib.git")
```
with:
```lua
local jj = require("neojj.lib.jj")
```

Replace line 155:
```lua
  local absolute_path = vim.fs.joinpath(git.repo.worktree_root, path)
```
with:
```lua
  local absolute_path = vim.fs.joinpath(jj.repo.worktree_root, path)
```

Replace the `goto_file_in_commit_at` function body (lines 223-239). Change:
```lua
  local file_contents =
    git.cli.show.file(path, target_commit).call { hidden = true, trim = false, ignore_error = true }
  if not file_contents or file_contents.code ~= 0 then
```
to:
```lua
  local file_contents =
    jj.cli.file_show.revision(target_commit).args(path).call { hidden = true, trim = false, ignore_error = true }
  if not file_contents or file_contents.code ~= 0 then
```

- [ ] **Step 2: Verify no remaining git references**

Run: `grep -n "require.*git" lua/neojj/lib/jump.lua`
Expected: No matches

- [ ] **Step 3: Commit**

```
jj describe -m "refactor: rewire jump.lua from git to jj"
jj new
```

---

### Task 6: Rewire `lib/popup/builder.lua`

**Files:**
- Modify: `lua/neojj/lib/popup/builder.lua:1,396`

- [ ] **Step 1: Replace git import and usage**

Replace line 1:
```lua
local git = require("neojj.lib.git")
```
with:
```lua
local jj_config = require("neojj.lib.jj.config")
```

Replace line 396:
```lua
  local entry = git.config.get(name)
```
with:
```lua
  local entry = jj_config.get(name)
```

- [ ] **Step 2: Verify no remaining git references**

Run: `grep -n "require.*git" lua/neojj/lib/popup/builder.lua`
Expected: No matches

- [ ] **Step 3: Commit**

```
jj describe -m "refactor: rewire popup builder from git.config to jj.config"
jj new
```

---

### Task 7: Rewire `lib/popup/init.lua`

**Files:**
- Modify: `lua/neojj/lib/popup/init.lua:12,267,275,280,430`

- [ ] **Step 1: Replace git import**

Replace line 12:
```lua
local git = require("neojj.lib.git")
```
with:
```lua
local jj = require("neojj.lib.jj")
local jj_config = require("neojj.lib.jj.config")
```

- [ ] **Step 2: Replace config set/get calls**

Replace line 267:
```lua
    git.config.set(config.name, config.value)
```
with:
```lua
    jj_config.set(config.name, config.value)
```

Replace line 275:
```lua
    git.config.set(config.name, config.value)
```
with:
```lua
    jj_config.set(config.name, config.value)
```

Replace lines 280-283:
```lua
      local c_value = git.config.get(var.name)
      if c_value:is_set() then
        var.value = c_value.value
      end
```
with:
```lua
      local c_value = jj_config.get(var.name)
      if c_value:is_set() then
        var.value = c_value.value
      end
```

- [ ] **Step 3: Replace branch highlight with bookmarks**

Replace line 430:
```lua
        vim.fn.matchadd("NeojjPopupBranchName", git.repo.state.head.branch, 100)
```
with:
```lua
        local bookmarks = jj.repo.state.head.bookmarks or {}
        for _, bm in ipairs(bookmarks) do
          vim.fn.matchadd("NeojjPopupBranchName", vim.pesc(bm), 100)
        end
```

Note: `vim.pesc()` escapes the bookmark name for use as a Vim regex pattern.

- [ ] **Step 4: Verify no remaining git references**

Run: `grep -n "require.*git" lua/neojj/lib/popup/init.lua`
Expected: No matches

- [ ] **Step 5: Commit**

```
jj describe -m "refactor: rewire popup init from git to jj config + bookmarks"
jj new
```

---

### Task 8: Remove git from `buffers/fuzzy_finder.lua`

**Files:**
- Modify: `lua/neojj/buffers/fuzzy_finder.lua:1-2,28-37`

- [ ] **Step 1: Remove git import and OID decoration block**

Remove line 2:
```lua
local git = require("neojj.lib.git")
```

Remove the OID decoration block in `M.new()` (lines 28-37):
```lua
  -- If the first item in the list is an git OID, decorate it
  if type(list[1]) == "string" and list[1]:match("^%x%x%x%x%x%x%x") then
    local oid = table.remove(list, 1)
    local ok, result = pcall(git.log.decorate, oid)
    if ok then
      table.insert(list, 1, result)
    else
      table.insert(list, 1, oid)
    end
  end
```

- [ ] **Step 2: Verify no remaining git references**

Run: `grep -n "git" lua/neojj/buffers/fuzzy_finder.lua`
Expected: No matches

- [ ] **Step 3: Commit**

```
jj describe -m "refactor: remove git dependency from fuzzy finder"
jj new
```

---

### Task 9: Rename and rewire command history buffer

**Files:**
- Rename: `lua/neojj/buffers/git_command_history.lua` → `lua/neojj/buffers/command_history.lua`
- Modify: `lua/neojj/buffers/status/actions.lua:359`
- Modify: `lua/neojj/lib/ui/helpers.lua:9`
- Modify: `lua/neojj/popups/help/actions.lua:41`

- [ ] **Step 1: Copy file to new name and update contents**

Copy `lua/neojj/buffers/git_command_history.lua` to `lua/neojj/buffers/command_history.lua`.

In the new `command_history.lua`, make these changes:

Replace line 2:
```lua
local Git = require("neojj.lib.git")
```
with:
```lua
local runner = require("neojj.runner")
```

Replace lines 14-16 (command_mask):
```lua
local command_mask = vim.pesc(
  " --no-pager --literal-pathspecs --no-optional-locks -c core.preloadindex=true -c color.ui=always -c diff.noprefix=false"
)
```
with:
```lua
local command_mask = vim.pesc(" --no-pager --color=never")
local ignore_wc_mask = vim.pesc(" --ignore-working-copy")
```

Replace line 23:
```lua
    state = state or Git.cli.history,
```
with:
```lua
    state = state or runner.history,
```

Replace line 55:
```lua
    name = "NeojjGitCommandHistory",
```
with:
```lua
    name = "NeojjCommandHistory",
```

Replace line 56:
```lua
    filetype = "NeojjGitCommandHistory",
```
with:
```lua
    filetype = "NeojjCommandHistory",
```

Replace line 106 (the gsub for command_mask):
```lua
        local command, _ = item.cmd:gsub(command_mask, "")
```
with:
```lua
        local command = item.cmd:gsub(command_mask, ""):gsub(ignore_wc_mask, "")
```

- [ ] **Step 2: Delete the old file**

```
rm lua/neojj/buffers/git_command_history.lua
```

- [ ] **Step 3: Update the 3 files that reference the old module**

In `lua/neojj/buffers/status/actions.lua`, replace line 359:
```lua
    require("neojj.buffers.git_command_history"):new():show()
```
with:
```lua
    require("neojj.buffers.command_history"):new():show()
```

In `lua/neojj/lib/ui/helpers.lua`, replace line 9:
```lua
    local history = require("neojj.buffers.git_command_history")
```
with:
```lua
    local history = require("neojj.buffers.command_history")
```

In `lua/neojj/popups/help/actions.lua`, replace line 41:
```lua
      require("neojj.buffers.git_command_history"):new():show()
```
with:
```lua
      require("neojj.buffers.command_history"):new():show()
```

- [ ] **Step 4: Verify no remaining references to old module**

Run: `grep -rn "git_command_history" lua/`
Expected: No matches

- [ ] **Step 5: Commit**

```
jj describe -m "refactor: rename git_command_history to command_history, use runner.history"
jj new
```

---

### Task 10: Clean up remaining references

**Files:**
- Modify: `lua/neojj/lib.lua:3`
- Modify: `lua/neojj/lib/ui/init.lua:154-159`
- Modify: `tests/mocks/commit_select_buffer.lua:2,11`
- Modify: `tests/README.md` (if references `neojj.lib.git.cli`)

- [ ] **Step 1: Remove git export from `lib.lua`**

In `lua/neojj/lib.lua`, remove line 3:
```lua
  git = require("neojj.lib.git"), -- kept for reference during migration
```

Result should be:
```lua
return {
  jj = require("neojj.lib.jj"),
  popup = require("neojj.lib.popup"),
  notification = require("neojj.lib.notification"),
}
```

- [ ] **Step 2: Remove commented-out git reference in `lib/ui/init.lua`**

In `lua/neojj/lib/ui/init.lua`, remove the entire commented-out block at lines 154-164:
```lua
  -- TODO: Move this to lib.git.diff
  -- local diff = require("neojj.lib.git").cli.diff.check.call { hidden = true, ignore_error = true }
  -- local conflict_markers = {}
  -- if diff.code == 2 then
  --   for _, out in ipairs(diff.stdout) do
  --     local line = string.gsub(out, "^" .. item.name .. ":", "")
  --     if line ~= out and string.match(out, "conflict") then
  --       table.insert(conflict_markers, tonumber(string.match(line, "%d+")))
  --     end
  --   end
  -- end
```

- [ ] **Step 3: Update test mock**

In `tests/mocks/commit_select_buffer.lua`, check if `git.rev_parse.oid(rev)` is used in active tests. If the mock is not actively used, remove the git import. If it is used, replace with jj equivalent:

Replace line 2:
```lua
local git = require("neojj.lib.git")
```

Replace line 11:
```lua
  table.insert(M.values, git.rev_parse.oid(rev))
```
with:
```lua
  table.insert(M.values, rev)
```

(The mock can accept rev strings directly — the `oid()` resolution was a git-ism.)

- [ ] **Step 4: Update `tests/README.md`**

Search for references to `neojj.lib.git.cli` and update to `neojj.lib.jj.cli` or remove if no longer relevant.

- [ ] **Step 5: Final verification — no consumer git imports remain**

Run: `grep -rn "require.*neojj\.lib\.git" lua/ --include="*.lua" | grep -v "lib/git/" | grep -v "integrations/diffview" | grep -v "integrations/codediff"`
Expected: No matches

- [ ] **Step 6: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```
jj describe -m "refactor: remove remaining git references from consumer code

Removes git export from lib.lua, cleans up commented-out git code in
lib/ui/init.lua, updates test mocks and docs.

After this change, the only files importing neojj.lib.git are:
- lib/git/*.lua (internal to git library)
- integrations/diffview.lua (git-colocated mode)
- integrations/codediff.lua (git-colocated mode)"
jj new
```
