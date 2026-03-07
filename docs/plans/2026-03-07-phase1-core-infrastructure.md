# Phase 1: Core jj Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the jj CLI builder, repository state, status parser, log parser, and diff module — the core backend that replaces `lib/git/`.

**Architecture:** Create a parallel `lua/neojj/lib/jj/` module tree that mirrors `lib/git/`. The existing `lib/git/` stays untouched for now. A new `lib/jj.lua` lazy-loader provides `jj.cli`, `jj.repo`, `jj.status`, `jj.log`, `jj.diff`, `jj.bookmark`. Process spawning (`process.lua`, `runner.lua`) is VCS-agnostic and reused as-is.

**Tech Stack:** Lua (Neovim plugin), jj CLI with `--no-pager --color=never`, JSON templates via `-T 'json(self)'`

---

### Task 1: Create jj module loader

**Files:**
- Create: `lua/neojj/lib/jj.lua`

**Context:** This mirrors `lua/neojj/lib/git.lua` — a lazy-loading module that auto-requires submodules when accessed. Everything will do `local jj = require("neojj.lib.jj")` then use `jj.cli`, `jj.repo`, etc.

**Step 1: Create the module loader**

```lua
-- lua/neojj/lib/jj.lua
---@class NeoJJLib
---@field repo    NeoJJRepo
---@field cli     NeoJJCLI
---@field status  NeoJJStatus
---@field log     NeoJJLog
---@field diff    NeoJJDiff
---@field bookmark NeoJJBookmark
local JJ = {}

setmetatable(JJ, {
  __index = function(_, k)
    if k == "repo" then
      return require("neojj.lib.jj.repository").instance()
    else
      return require("neojj.lib.jj." .. k)
    end
  end,
})

return JJ
```

**Step 2: Verify module loads**

```bash
cd /Users/nicholas/Documents/Projects/NeoJJ
nvim --headless -c "lua print(vim.inspect(require('neojj.lib.jj')))" -c "qa!" 2>&1
```

Expected: No errors (will fail on submodule requires but the loader itself should work)

**Step 3: Commit**

```bash
git add lua/neojj/lib/jj.lua
git commit -m "feat(jj): add jj module lazy-loader"
```

---

### Task 2: Create jj CLI builder

**Files:**
- Create: `lua/neojj/lib/jj/cli.lua`
- Reference: `lua/neojj/lib/git/cli.lua` (same builder pattern)
- Reference: `lua/neojj/process.lua` (for Process creation)

**Context:** This is the core of the jj backend. It provides a fluent API for building jj commands:
```lua
jj.cli.log.no_graph.template("json(self)").revisions("@").call()
jj.cli.status.call()
jj.cli.diff.summary.revision("@").call()
```

The builder pattern works via Lua metatables. Each command has a config defining its flags/options. Accessing a flag name on the builder sets it. `.call(opts)` executes the command.

**Important jj global flags** (applied to every command):
- `--no-pager` — disable pagination
- `--color=never` — no ANSI codes
- `--ignore-working-copy` — skip auto-snapshot for faster reads (use on read-only commands)

**Step 1: Create the CLI builder**

Create `lua/neojj/lib/jj/cli.lua` with this structure:

```lua
local Process = require("neojj.process")
local runner = require("neojj.runner")

local M = {}

-- Private metatable keys
local k_state = {}
local k_config = {}
local k_command = {}

-- Builder metatable
local mt_builder = {}

mt_builder.__index = function(tbl, action)
  local state = rawget(tbl, k_state)
  local config = rawget(tbl, k_config)

  -- Built-in methods
  if action == "args" or action == "arguments" then
    return function(...)
      for _, v in ipairs { ... } do
        table.insert(state.arguments, v)
      end
      return tbl
    end
  elseif action == "files" or action == "paths" then
    return function(...)
      for _, v in ipairs { ... } do
        table.insert(state.files, v)
      end
      return tbl
    end
  elseif action == "input" or action == "stdin" then
    return function(value)
      state.input = value
      return tbl
    end
  elseif action == "env" then
    return function(cfg)
      state.env = vim.tbl_extend("force", state.env, cfg)
      return tbl
    end
  elseif action == "in_pty" then
    return function(v)
      state.in_pty = v
      return tbl
    end
  elseif action == "call" then
    return function(opts)
      return M._call(tbl, opts)
    end
  elseif action == "to_process" then
    return function(opts)
      return M._to_process(tbl, opts)
    end
  end

  -- Config-defined flags
  if config.flags and config.flags[action] then
    table.insert(state.options, config.flags[action])
    return tbl
  end

  -- Config-defined options (key=value)
  if config.options and config.options[action] then
    return function(value)
      if value then
        table.insert(state.options, config.options[action] .. "=" .. tostring(value))
      else
        table.insert(state.options, config.options[action])
      end
      return tbl
    end
  end

  -- Config-defined short_opts (-x value)
  if config.short_opts and config.short_opts[action] then
    return function(value)
      table.insert(state.options, config.short_opts[action])
      table.insert(state.options, tostring(value))
      return tbl
    end
  end

  -- Config-defined aliases (custom functions)
  if config.aliases and config.aliases[action] then
    return config.aliases[action](tbl, state)
  end

  error("Unknown flag/option for jj " .. rawget(tbl, k_command) .. ": " .. action)
end

mt_builder.__tostring = function(tbl)
  local state = rawget(tbl, k_state)
  local cmd = rawget(tbl, k_command)
  local parts = { "jj", cmd }
  vim.list_extend(parts, state.options)
  vim.list_extend(parts, state.arguments)
  vim.list_extend(parts, state.files)
  return table.concat(parts, " ")
end

-- Create a new builder for a subcommand
local function new_builder(command, config)
  local builder = setmetatable({
    [k_state] = {
      options = {},
      arguments = {},
      files = {},
      input = nil,
      in_pty = false,
      env = {},
    },
    [k_config] = config or {},
    [k_command] = command,
  }, mt_builder)
  return builder
end

---Build command array from builder state
---@param tbl table Builder instance
---@return string[] command array
function M._build_cmd(tbl)
  local state = rawget(tbl, k_state)
  local command = rawget(tbl, k_command)

  local cmd = { "jj", "--no-pager", "--color=never" }

  -- Add --ignore-working-copy for read-only commands
  local readonly_commands = {
    log = true, diff = true, show = true, status = true,
    ["bookmark list"] = true, ["op log"] = true,
    ["file list"] = true, ["file annotate"] = true,
  }
  if readonly_commands[command] then
    table.insert(cmd, "--ignore-working-copy")
  end

  -- Add subcommand (may be multi-word like "git push")
  for word in command:gmatch("%S+") do
    table.insert(cmd, word)
  end

  -- Add options, arguments, files
  vim.list_extend(cmd, state.options)
  vim.list_extend(cmd, state.arguments)
  if #state.files > 0 then
    vim.list_extend(cmd, state.files)
  end

  return cmd
end

---Convert builder to Process object
function M._to_process(tbl, opts)
  local state = rawget(tbl, k_state)
  local jj = require("neojj.lib.jj")
  local cmd = M._build_cmd(tbl)

  return Process.new {
    cmd = cmd,
    cwd = jj.repo.worktree_root,
    env = state.env,
    input = state.input,
    pty = state.in_pty,
    on_error = opts and opts.on_error or nil,
  }
end

---Execute the command
function M._call(tbl, opts)
  opts = opts or {}
  local defaults = {
    hidden = true,
    trim = true,
    remove_ansi = true,
    await = false,
    long = false,
    pty = false,
  }
  opts = vim.tbl_extend("keep", opts, defaults)

  local process = M._to_process(tbl, opts)
  return runner.call(process, opts)
end

-- ============================================================
-- Command Configurations
-- ============================================================

-- Helper to define a command with its config
local function config(name, cfg)
  M[name] = setmetatable({}, {
    __index = function(_, _)
      return new_builder(name, cfg)
    end,
    __call = function(_)
      return new_builder(name, cfg)
    end,
  })
end

-- Simpler: make each command accessible as a property that returns a fresh builder
local commands = {}

local function define_command(name, cfg)
  commands[name] = cfg or {}
end

-- jj status
define_command("status", {
  flags = {
    no_pager = "--no-pager",
  },
})

-- jj log
define_command("log", {
  flags = {
    no_graph = "--no-graph",
    patch = "-p",
    summary = "-s",
    stat = "--stat",
    reversed = "--reversed",
  },
  options = {
    template = "-T",
    revisions = "-r",
    limit = "-n",
  },
})

-- jj diff
define_command("diff", {
  flags = {
    summary = "-s",
    stat = "--stat",
    git = "--git",
    color_words = "--color-words",
    types = "--types",
    name_only = "--name-only",
  },
  options = {
    revision = "-r",
    from = "--from",
    to = "--to",
    context = "--context",
    tool = "--tool",
  },
})

-- jj show
define_command("show", {
  flags = {
    summary = "-s",
    stat = "--stat",
    git = "--git",
    color_words = "--color-words",
  },
  options = {
    template = "-T",
    revision = "-r",
    tool = "--tool",
  },
})

-- jj describe
define_command("describe", {
  flags = {
    no_edit = "--no-edit",
    reset_author = "--reset-author",
    stdin = "--stdin",
  },
  options = {
    message = "-m",
    revision = "-r",
  },
})

-- jj new
define_command("new", {
  flags = {
    no_edit = "--no-edit",
    insert_before = "--insert-before",
    insert_after = "--insert-after",
  },
  options = {
    message = "-m",
    revision = "-r",
  },
  aliases = {
    -- Allow passing multiple revision args directly
    revisions = function(tbl, state)
      return function(...)
        for _, v in ipairs { ... } do
          table.insert(state.arguments, v)
        end
        return tbl
      end
    end,
  },
})

-- jj commit
define_command("commit", {
  flags = {
    reset_author = "--reset-author",
  },
  options = {
    message = "-m",
  },
})

-- jj squash
define_command("squash", {
  flags = {
    interactive = "-i",
  },
  options = {
    revision = "-r",
    from = "--from",
    into = "--into",
    message = "-m",
  },
})

-- jj split
define_command("split", {
  flags = {
    interactive = "-i",
  },
  options = {
    revision = "-r",
  },
})

-- jj abandon
define_command("abandon", {
  options = {
    revision = "-r",
  },
})

-- jj restore
define_command("restore", {
  options = {
    from = "--from",
    to = "--to",
    revision = "-r",
  },
})

-- jj rebase
define_command("rebase", {
  flags = {
    skip_emptied = "--skip-emptied",
  },
  options = {
    source = "-s",
    branch = "-b",
    revision = "-r",
    destination = "-d",
    before = "--before",
    after = "--after",
  },
})

-- jj duplicate
define_command("duplicate", {
  options = {
    revision = "-r",
    destination = "-d",
  },
})

-- jj resolve
define_command("resolve", {
  flags = {
    list = "--list",
  },
  options = {
    revision = "-r",
    tool = "--tool",
  },
})

-- jj bookmark list
define_command("bookmark list", {
  flags = {
    all_remotes = "--all-remotes",
  },
  options = {
    template = "-T",
    revisions = "-r",
  },
})

-- jj bookmark create
define_command("bookmark create", {
  options = {
    revision = "-r",
  },
})

-- jj bookmark move
define_command("bookmark move", {
  flags = {
    allow_backwards = "--allow-backwards",
  },
  options = {
    to = "--to",
    from = "--from",
  },
})

-- jj bookmark delete
define_command("bookmark delete", {})

-- jj bookmark forget
define_command("bookmark forget", {})

-- jj bookmark track
define_command("bookmark track", {})

-- jj git push
define_command("git push", {
  flags = {
    all = "--all",
    dry_run = "--dry-run",
    deleted = "--deleted",
  },
  options = {
    bookmark = "--bookmark",
    change = "--change",
    remote = "--remote",
    revisions = "--revisions",
  },
})

-- jj git fetch
define_command("git fetch", {
  flags = {
    all_remotes = "--all-remotes",
  },
  options = {
    remote = "--remote",
    bookmark = "--bookmark",
  },
})

-- jj git remote add
define_command("git remote add", {})

-- jj git remote remove
define_command("git remote remove", {})

-- jj git remote rename
define_command("git remote rename", {})

-- jj git remote list
define_command("git remote list", {})

-- jj undo
define_command("undo", {})

-- jj op log
define_command("op log", {
  flags = {
    no_graph = "--no-graph",
  },
  options = {
    template = "-T",
    limit = "-n",
  },
})

-- jj op restore
define_command("op restore", {})

-- jj revert
define_command("revert", {
  options = {
    revision = "-r",
    destination = "-d",
  },
})

-- jj diffedit
define_command("diffedit", {
  options = {
    revision = "-r",
    from = "--from",
    to = "--to",
  },
})

-- jj file list
define_command("file list", {
  options = {
    revision = "-r",
  },
})

-- jj file untrack
define_command("file untrack", {})

-- jj file annotate
define_command("file annotate", {})

-- jj workspace root
define_command("workspace root", {})

-- jj absorb
define_command("absorb", {
  options = {
    from = "--from",
    into = "--into",
  },
})

-- jj parallelize
define_command("parallelize", {})

-- ============================================================
-- Module metatable: access commands as properties
-- ============================================================

setmetatable(M, {
  __index = function(_, k)
    -- Normalize underscores to spaces for multi-word commands
    -- e.g., M.git_push → "git push", M.bookmark_list → "bookmark list"
    -- But single-word commands stay as-is: M.log → "log"
    local command_name = k:gsub("_", " ")
    local cfg = commands[command_name]
    if cfg then
      return new_builder(command_name, cfg)
    end

    -- Also try exact name (for single-word commands)
    cfg = commands[k]
    if cfg then
      return new_builder(k, cfg)
    end

    error("Unknown jj command: " .. k)
  end,
})

-- ============================================================
-- Utility functions
-- ============================================================

---Get the workspace root directory
---@param dir? string Directory to check from
---@return string|nil root
function M.workspace_root(dir)
  local result = Process.new({
    cmd = { "jj", "--no-pager", "--color=never", "workspace", "root" },
    cwd = dir or vim.fn.getcwd(),
  }):spawn_blocking()

  if result and result.code == 0 and result.stdout[1] then
    return result.stdout[1]:gsub("%s+$", "")
  end
  return nil
end

---Check if directory is inside a jj workspace
---@param dir? string Directory to check
---@return boolean
function M.is_inside_workspace(dir)
  return M.workspace_root(dir) ~= nil
end

return M
```

**Step 2: Verify CLI builder loads and builds commands**

```bash
nvim --headless -c "lua local cli = require('neojj.lib.jj.cli'); print(tostring(cli.log.no_graph.revisions('@')))" -c "qa!" 2>&1
```

Expected: `jj log --no-graph -r=@` (or similar string representation)

**Step 3: Commit**

```bash
git add lua/neojj/lib/jj/cli.lua
git commit -m "feat(jj): add jj CLI fluent builder with all commands"
```

---

### Task 3: Create jj repository state and refresh mechanism

**Files:**
- Create: `lua/neojj/lib/jj/repository.lua`
- Reference: `lua/neojj/lib/git/repository.lua` (same pattern)

**Context:** The repository module holds the central state that the UI reads from. It provides:
- `Repo.instance()` — singleton per directory
- `repo.state` — all parsed jj data
- `repo:refresh()` — re-query jj and update state
- `repo:dispatch_refresh()` — async wrapper

**Step 1: Create the repository module**

```lua
-- lua/neojj/lib/jj/repository.lua
local a = require("plenary.async")
local logger = require("neojj.logger")

---@class NeoJJRepoHead
---@field change_id string Short change ID
---@field commit_id string Short commit ID
---@field description string Change description
---@field bookmarks string[] Bookmarks pointing to this change
---@field empty boolean Whether the change is empty
---@field conflict boolean Whether the change has conflicts

---@class NeoJJRepoParent
---@field change_id string
---@field commit_id string
---@field description string
---@field bookmarks string[]

---@class NeoJJFileItem
---@field name string File path
---@field absolute_path string Full file path
---@field escaped_path string Vim-escaped path
---@field mode string "M", "A", "D", "R"
---@field original_name string|nil For renames
---@field diff any|nil Lazy-loaded diff
---@field folded boolean|nil

---@class NeoJJConflictItem
---@field name string File path
---@field absolute_path string
---@field escaped_path string

---@class NeoJJChangeLogEntry
---@field change_id string
---@field commit_id string
---@field description string
---@field author_name string
---@field author_email string
---@field author_date string
---@field bookmarks string[]
---@field empty boolean
---@field conflict boolean
---@field immutable boolean
---@field current_working_copy boolean
---@field graph string|nil Graph ASCII art

---@class NeoJJBookmarkItem
---@field name string
---@field change_id string
---@field commit_id string
---@field description string
---@field remote string|nil Remote name if tracking bookmark

---@class NeoJJRepoState
---@field worktree_root string
---@field head NeoJJRepoHead
---@field parent NeoJJRepoParent
---@field files { items: NeoJJFileItem[] }
---@field conflicts { items: NeoJJConflictItem[] }
---@field recent { items: NeoJJChangeLogEntry[] }
---@field bookmarks { items: NeoJJBookmarkItem[] }

local M = {}

---@return NeoJJRepoState
local function empty_state()
  return {
    worktree_root = "",
    head = {
      change_id = "",
      commit_id = "",
      description = "",
      bookmarks = {},
      empty = true,
      conflict = false,
    },
    parent = {
      change_id = "",
      commit_id = "",
      description = "",
      bookmarks = {},
    },
    files = { items = {} },
    conflicts = { items = {} },
    recent = { items = {} },
    bookmarks = { items = {} },
  }
end

---@class NeoJJRepo
---@field state NeoJJRepoState
---@field lib table<string, { update: fun(state: NeoJJRepoState) }>
local Repo = {}
Repo.__index = Repo

local instances = {}

---Get or create singleton repo instance for a directory
---@param dir? string
---@return NeoJJRepo
function Repo.instance(dir)
  local jj_cli = require("neojj.lib.jj.cli")
  dir = dir or vim.fn.getcwd()
  dir = vim.fn.fnamemodify(dir, ":p")

  if not instances[dir] then
    local root = jj_cli.workspace_root(dir)
    if not root then
      error("Not inside a jj workspace: " .. dir)
    end
    instances[dir] = Repo.new(root)
  end

  return instances[dir]
end

---Create a new repo instance
---@param root string Workspace root directory
---@return NeoJJRepo
function Repo.new(root)
  local self = setmetatable({}, Repo)
  self.state = empty_state()
  self.state.worktree_root = root
  self.worktree_root = root
  self.running = false
  self.callbacks = {}

  -- Register library modules for refresh
  self.lib = {}

  return self
end

---Register a refresh module
---@param name string
---@param mod table Module with update(state) function
function Repo:register(name, mod)
  self.lib[name] = mod
end

---Register a callback to run after next refresh
function Repo:register_callback(source, fn)
  self.callbacks[source] = fn
end

---Run and clear all registered callbacks
function Repo:run_callbacks()
  local cbs = self.callbacks
  self.callbacks = {}
  for _, fn in pairs(cbs) do
    fn()
  end
end

---Reset state to empty
function Repo:reset()
  self.state = empty_state()
  self.state.worktree_root = self.worktree_root
end

---Build async task list from registered modules
---@return function[]
function Repo:tasks()
  local tasks = {}
  for name, mod in pairs(self.lib) do
    if mod.update then
      table.insert(tasks, function()
        local start = vim.uv.hrtime()
        mod.update(self.state)
        local elapsed = (vim.uv.hrtime() - start) / 1e6
        logger.trace(("[REPO] %s updated in %.1fms"):format(name, elapsed))
      end)
    end
  end
  return tasks
end

---Refresh all state from jj
---@param opts? { callback?: fun(), source?: string }
function Repo:refresh(opts)
  opts = opts or {}

  if opts.callback and opts.source then
    self:register_callback(opts.source, opts.callback)
  end

  local tasks = self:tasks()
  if #tasks > 0 then
    a.util.run_all(tasks, function()
      self:run_callbacks()
    end)
  else
    self:run_callbacks()
  end
end

---Async dispatch refresh
function Repo:dispatch_refresh(opts)
  a.run(function()
    self:refresh(opts)
  end)
end

M.instance = Repo.instance
M.Repo = Repo

return M
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/repository.lua
git commit -m "feat(jj): add repository state and refresh mechanism"
```

---

### Task 4: Create jj status parser

**Files:**
- Create: `lua/neojj/lib/jj/status.lua`

**Context:** Parses `jj status` to extract:
- Current change info (change_id, commit_id, description)
- Parent change info
- Modified files list

`jj status` output format:
```
Working copy changes:
M hello.txt
A src.lua
Working copy  (@) : muvqvxnn 7809cff3 (no description set)
Parent commit (@-): tvonrrpo 63990385 main | initial commit
```

Also uses `jj diff --summary` for file changes and `jj log --no-graph -T 'json(self)' -r '@'` for structured change data.

**Step 1: Create the status parser**

```lua
-- lua/neojj/lib/jj/status.lua
local M = {}

---@class NeoJJStatusMeta
local meta = {}

---Parse `jj diff --summary` output into file items
---@param lines string[]
---@param root string Workspace root for absolute paths
---@return NeoJJFileItem[]
function M.parse_diff_summary(lines, root)
  local items = {}
  for _, line in ipairs(lines) do
    local mode, name = line:match("^(%a)%s+(.+)$")
    if mode and name then
      table.insert(items, {
        name = name,
        mode = mode,
        absolute_path = root .. "/" .. name,
        escaped_path = vim.fn.fnameescape(name),
        original_name = nil,
        diff = nil,
        folded = nil,
      })
    else
      -- Handle renames: R {old_path} → {new_path}  (hypothetical)
      local rmode, old, new = line:match("^(%a)%s+(%S+)%s+(.+)$")
      if rmode == "R" and old and new then
        table.insert(items, {
          name = new,
          mode = "R",
          absolute_path = root .. "/" .. new,
          escaped_path = vim.fn.fnameescape(new),
          original_name = old,
          diff = nil,
          folded = nil,
        })
      end
    end
  end
  return items
end

---Parse `jj status` output for working copy and parent info
---@param lines string[]
---@return { head: NeoJJRepoHead, parent: NeoJJRepoParent }
function M.parse_status_lines(lines)
  local head = {
    change_id = "",
    commit_id = "",
    description = "",
    bookmarks = {},
    empty = true,
    conflict = false,
  }
  local parent = {
    change_id = "",
    commit_id = "",
    description = "",
    bookmarks = {},
  }

  for _, line in ipairs(lines) do
    -- Working copy  (@) : <change_id> <commit_id> [bookmarks] <description>
    local wc_rest = line:match("^Working copy%s+%(@%)%s*:%s*(.+)$")
    if wc_rest then
      local change_id, commit_id, rest = wc_rest:match("^(%S+)%s+(%S+)%s*(.*)")
      if change_id then
        head.change_id = change_id
        head.commit_id = commit_id
        head.description = rest or ""
        head.empty = rest and rest:match("%(empty%)") ~= nil or false
        head.conflict = rest and rest:match("%(conflict%)") ~= nil or false
      end
    end

    -- Parent commit (@-): <change_id> <commit_id> [bookmarks |] <description>
    local pc_rest = line:match("^Parent commit%s+%(@%-%)?:%s*(.+)$")
    if pc_rest then
      local change_id, commit_id, rest = pc_rest:match("^(%S+)%s+(%S+)%s*(.*)")
      if change_id then
        parent.change_id = change_id
        parent.commit_id = commit_id
        -- Parse bookmarks before the | separator
        local bookmark_part, desc = rest:match("^(.-)%s*|%s*(.*)$")
        if bookmark_part and #bookmark_part > 0 then
          for bm in bookmark_part:gmatch("%S+") do
            table.insert(parent.bookmarks, bm)
          end
          parent.description = desc or ""
        else
          parent.description = rest or ""
        end
      end
    end
  end

  return { head = head, parent = parent }
end

---Parse conflict file list from `jj status` output
---@param lines string[]
---@param root string
---@return NeoJJConflictItem[]
function M.parse_conflicts(lines, root)
  local conflicts = {}
  local in_conflicts = false

  for _, line in ipairs(lines) do
    if line:match("^There are unresolved conflicts") then
      in_conflicts = true
    elseif in_conflicts then
      local name = line:match("^%s+(.+)$")
      if name then
        table.insert(conflicts, {
          name = name,
          absolute_path = root .. "/" .. name,
          escaped_path = vim.fn.fnameescape(name),
        })
      else
        in_conflicts = false
      end
    end
  end

  return conflicts
end

---Update repository state with jj status data
---@param state NeoJJRepoState
function meta.update(state)
  local jj = require("neojj.lib.jj")

  -- Get file changes
  local diff_result = jj.cli.diff.summary.call { hidden = true, trim = true }
  if diff_result and diff_result.code == 0 then
    state.files.items = M.parse_diff_summary(diff_result.stdout, state.worktree_root)
  end

  -- Get status (working copy + parent info)
  local status_result = jj.cli.status.call { hidden = true, trim = true }
  if status_result and status_result.code == 0 then
    local parsed = M.parse_status_lines(status_result.stdout)
    -- Merge into head/parent (don't overwrite completely, enrich)
    state.head.change_id = parsed.head.change_id
    state.head.commit_id = parsed.head.commit_id
    state.head.empty = parsed.head.empty
    state.head.conflict = parsed.head.conflict
    if parsed.head.description ~= "" then
      state.head.description = parsed.head.description
    end
    state.parent.change_id = parsed.parent.change_id
    state.parent.commit_id = parsed.parent.commit_id
    state.parent.description = parsed.parent.description
    state.parent.bookmarks = parsed.parent.bookmarks

    -- Parse conflicts
    state.conflicts.items = M.parse_conflicts(status_result.stdout, state.worktree_root)
  end
end

M.meta = meta

return M
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/status.lua
git commit -m "feat(jj): add status parser for jj status and diff summary"
```

---

### Task 5: Create jj log parser

**Files:**
- Create: `lua/neojj/lib/jj/log.lua`

**Context:** Parses `jj log` output. Uses JSON templates for structured data:
```
jj log --no-graph -T 'json(self)' -r 'ancestors(@, 10)'
```

JSON output is concatenated objects `{...}{...}{...}` with no separator.

Also parses the graph version for display in the log view.

**Step 1: Create the log parser**

```lua
-- lua/neojj/lib/jj/log.lua
local M = {}

---@class NeoJJLogMeta
local meta = {}

---Parse concatenated JSON objects from jj log -T 'json(self)'
---Handles the format: {...}{...}{...} with no separator
---@param text string Raw JSON output
---@return table[] Array of decoded objects
function M.parse_json_objects(text)
  local objects = {}
  local depth = 0
  local start = nil

  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "{" then
      if depth == 0 then
        start = i
      end
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 and start then
        local json_str = text:sub(start, i)
        local ok, obj = pcall(vim.json.decode, json_str)
        if ok and obj then
          table.insert(objects, obj)
        end
        start = nil
      end
    end
  end

  return objects
end

---Convert a JSON commit object to a ChangeLogEntry
---@param obj table Decoded JSON object from jj log -T 'json(self)'
---@return NeoJJChangeLogEntry
function M.json_to_entry(obj)
  return {
    change_id = obj.change_id or "",
    commit_id = obj.commit_id or "",
    description = (obj.description or ""):gsub("\n$", ""),
    author_name = obj.author and obj.author.name or "",
    author_email = obj.author and obj.author.email or "",
    author_date = obj.author and obj.author.timestamp or "",
    bookmarks = {},  -- Not in json(self), enriched separately
    empty = false,   -- Not in json(self), enriched separately
    conflict = false,-- Not in json(self), enriched separately
    immutable = false,
    current_working_copy = false,
    graph = nil,
  }
end

---Parse graph lines from `jj log` default output (with graph)
---Returns entries with graph characters and basic info parsed from the display format
---@param lines string[]
---@return NeoJJChangeLogEntry[]
function M.parse_graph(lines)
  local entries = {}
  local current = nil

  for _, line in ipairs(lines) do
    -- Match commit line: graph_chars change_id email date time commit_id
    -- Examples:
    --   @  muvqvxnn nick@email 2026-03-07 02:38 7809cff3
    --   ○  tvonrrpo nick@email 2026-03-07 02:38 main 63990385
    --   ◆  zzzzzzzz root() 00000000
    local graph, rest = line:match("^([@○◆│╭╮├┤┬┴─┼%s|/\\*%.]+)(%S.*)$")
    if graph and rest then
      -- Try to parse as a commit line
      local change_id, remainder = rest:match("^(%S+)%s+(.+)$")
      if change_id and change_id:match("^%a+$") then
        -- This looks like a change ID line
        current = {
          change_id = change_id,
          commit_id = "",
          description = "",
          author_name = "",
          author_email = "",
          author_date = "",
          bookmarks = {},
          empty = false,
          conflict = false,
          immutable = graph:match("◆") ~= nil,
          current_working_copy = graph:match("@") ~= nil,
          graph = graph,
        }

        -- Parse rest: email date time [bookmarks] commit_id
        -- This is best-effort since the format is configurable
        local parts = {}
        for part in remainder:gmatch("%S+") do
          table.insert(parts, part)
        end

        if #parts >= 1 then
          -- Last part is usually the commit ID (hex string)
          local last = parts[#parts]
          if last:match("^%x+$") then
            current.commit_id = last
          end
        end

        table.insert(entries, current)
      end
    elseif current then
      -- Description line (indented under the commit)
      local desc = line:match("^[│|%s]+(.+)$")
      if desc and #desc > 0 and not desc:match("^[│|/\\%s]*$") then
        if current.description == "" then
          current.description = desc
        end
      end
    end
  end

  return entries
end

---Fetch recent changes via JSON template
---@param revset? string Revset expression (default: ancestors(@, 20))
---@param limit? number Max entries
---@return NeoJJChangeLogEntry[]
function M.list(revset, limit)
  local jj = require("neojj.lib.jj")
  limit = limit or 20
  revset = revset or ("ancestors(@, " .. limit .. ")")

  local result = jj.cli.log.no_graph
    .template("json(self)")
    .revisions(revset)
    .call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  local text = table.concat(result.stdout, "")
  local objects = M.parse_json_objects(text)

  local entries = {}
  for _, obj in ipairs(objects) do
    table.insert(entries, M.json_to_entry(obj))
  end

  return entries
end

---Update repository state with recent changes
---@param state NeoJJRepoState
function meta.update(state)
  local entries = M.list(nil, 20)
  state.recent.items = entries

  -- Enrich head description from log if status didn't provide it
  if #entries > 0 and state.head.change_id ~= "" then
    for _, entry in ipairs(entries) do
      if entry.change_id == state.head.change_id
        or state.head.change_id:find(entry.change_id, 1, true) == 1
        or entry.change_id:find(state.head.change_id, 1, true) == 1 then
        if entry.description ~= "" and (state.head.description == "" or state.head.description:match("^%(")) then
          state.head.description = entry.description
        end
        break
      end
    end
  end
end

M.meta = meta

return M
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/log.lua
git commit -m "feat(jj): add log parser with JSON template and graph support"
```

---

### Task 6: Create jj diff module

**Files:**
- Create: `lua/neojj/lib/jj/diff.lua`
- Reference: `lua/neojj/lib/git/diff.lua` (reuse its hunk parser since `jj diff --git` outputs standard unified diff)

**Context:** `jj diff --git` produces standard git-format unified diffs. The existing `lib/git/diff.lua` hunk parser can be reused. This module wraps jj-specific diff commands and delegates parsing.

**Step 1: Create the diff module**

```lua
-- lua/neojj/lib/jj/diff.lua
local M = {}

---@class NeoJJDiffMeta
local meta = {}

---Get diff for the working copy change (or a specific revision)
---@param revision? string Revision to diff (default: working copy @)
---@return string[] Raw diff lines in git format
function M.raw(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.git
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff between two revisions
---@param from string Source revision
---@param to string Target revision
---@return string[] Raw diff lines in git format
function M.raw_range(from, to)
  local jj = require("neojj.lib.jj")
  local result = jj.cli.diff.git.from(from).to(to).call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff summary for a revision
---@param revision? string
---@return string[] Summary lines (e.g., "M file.txt")
function M.summary(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.summary
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff stat
---@param revision? string
---@return string[] Stat lines
function M.stat(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.stat
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Build diff for a specific file item (lazy loading)
---@param item NeoJJFileItem
---@param revision? string
---@return string[] Raw diff lines for this file
function M.file_diff(item, revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.git
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.files(item.name).call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

M.meta = meta

return M
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/diff.lua
git commit -m "feat(jj): add diff module wrapping jj diff --git"
```

---

### Task 7: Create jj bookmark module

**Files:**
- Create: `lua/neojj/lib/jj/bookmark.lua`

**Context:** Manages bookmarks (jj's equivalent of git branches). Parses `jj bookmark list` and provides CRUD operations.

**Step 1: Create the bookmark module**

```lua
-- lua/neojj/lib/jj/bookmark.lua
local M = {}

---@class NeoJJBookmarkMeta
local meta = {}

---Parse `jj bookmark list` output
---Format: "name: change_id commit_id [| ] description"
---Remote: "  @remote: change_id commit_id description"
---@param lines string[]
---@return NeoJJBookmarkItem[]
function M.parse_list(lines)
  local items = {}
  local current_name = nil

  for _, line in ipairs(lines) do
    -- Remote tracking bookmark: "  @remote: change_id commit_id desc"
    local remote, rchange, rcommit, rdesc = line:match("^%s+@(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
    if remote and current_name then
      table.insert(items, {
        name = current_name,
        change_id = rchange,
        commit_id = rcommit,
        description = (rdesc or ""):gsub("^|%s*", ""),
        remote = remote,
      })
    else
      -- Local bookmark: "name: change_id commit_id [| ] desc"
      local name, change_id, commit_id, rest = line:match("^(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
      if name then
        current_name = name
        local desc = (rest or ""):gsub("^|%s*", "")
        table.insert(items, {
          name = name,
          change_id = change_id,
          commit_id = commit_id,
          description = desc,
          remote = nil,
        })
      end
    end
  end

  return items
end

---List all bookmarks
---@return NeoJJBookmarkItem[]
function M.list()
  local jj = require("neojj.lib.jj")
  local result = jj.cli.bookmark_list.all_remotes.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return M.parse_list(result.stdout)
  end
  return {}
end

---Create a bookmark
---@param name string
---@param revision? string
function M.create(name, revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_create.args(name)
  if revision then
    builder = builder.revision(revision)
  end
  return builder.call()
end

---Move a bookmark
---@param name string
---@param to string Target revision
---@param allow_backwards? boolean
function M.move(name, to, allow_backwards)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_move.args(name).to(to)
  if allow_backwards then
    builder = builder.allow_backwards
  end
  return builder.call()
end

---Delete a bookmark
---@param name string
function M.delete(name)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_delete.args(name).call()
end

---Track a remote bookmark
---@param bookmark_at_remote string e.g., "main@origin"
function M.track(bookmark_at_remote)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_track.args(bookmark_at_remote).call()
end

---Forget a bookmark
---@param name string
function M.forget(name)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_forget.args(name).call()
end

---Update repository state with bookmark data
---@param state NeoJJRepoState
function meta.update(state)
  state.bookmarks.items = M.list()
end

M.meta = meta

return M
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/bookmark.lua
git commit -m "feat(jj): add bookmark module with list/create/move/delete/track"
```

---

### Task 8: Wire up repository refresh with all modules

**Files:**
- Modify: `lua/neojj/lib/jj/repository.lua`

**Context:** Now that all modules exist, register them with the repository so `repo:refresh()` populates state from all sources.

**Step 1: Update Repo.new to register modules**

In `lua/neojj/lib/jj/repository.lua`, update `Repo.new` to register all lib modules:

```lua
function Repo.new(root)
  local self = setmetatable({}, Repo)
  self.state = empty_state()
  self.state.worktree_root = root
  self.worktree_root = root
  self.running = false
  self.callbacks = {}

  -- Register library modules for refresh
  self.lib = {}
  self:register("status", require("neojj.lib.jj.status").meta)
  self:register("log", require("neojj.lib.jj.log").meta)
  self:register("bookmark", require("neojj.lib.jj.bookmark").meta)

  return self
end
```

**Step 2: Commit**

```bash
git add lua/neojj/lib/jj/repository.lua
git commit -m "feat(jj): wire up status, log, bookmark modules in repository refresh"
```

---

### Task 9: Verify the full jj backend works end-to-end

**Context:** Run a headless Neovim test that loads the jj backend and verifies it can parse real jj output. This requires being inside a jj repo. If the current repo isn't a jj repo, create a temp one for testing.

**Step 1: Create a simple integration test script**

Create `tests/jj_backend_test.lua`:

```lua
-- Manual integration test for jj backend
-- Run: nvim --headless -u NONE -l tests/jj_backend_test.lua

-- Add plugin to runtimepath
vim.opt.rtp:prepend(".")

local ok, err

-- Test 1: Module loader
ok, err = pcall(require, "neojj.lib.jj")
print(ok and "PASS" or "FAIL", "jj module loader:", err or "loaded")

-- Test 2: CLI builder string representation
ok, err = pcall(function()
  local cli = require("neojj.lib.jj.cli")
  local cmd = cli.log.no_graph.revisions("@")
  local str = tostring(cmd)
  assert(str:find("jj"), "Expected 'jj' in command string")
  assert(str:find("log"), "Expected 'log' in command string")
  assert(str:find("no%-graph") or str:find("%-%-no%-graph"), "Expected '--no-graph' in command string")
  print("  Command string:", str)
end)
print(ok and "PASS" or "FAIL", "CLI builder:", err or "builds commands")

-- Test 3: JSON parser
ok, err = pcall(function()
  local log = require("neojj.lib.jj.log")
  local objects = log.parse_json_objects('{"a":1}{"b":2}{"c":3}')
  assert(#objects == 3, "Expected 3 objects, got " .. #objects)
  assert(objects[1].a == 1)
  assert(objects[2].b == 2)
  assert(objects[3].c == 3)
end)
print(ok and "PASS" or "FAIL", "JSON parser:", err or "parses concatenated objects")

-- Test 4: Status parser
ok, err = pcall(function()
  local status = require("neojj.lib.jj.status")
  local lines = {
    "Working copy changes:",
    "M hello.txt",
    "A src.lua",
    'Working copy  (@) : muvqvxnn 7809cff3 (no description set)',
    "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
  }
  local parsed = status.parse_status_lines(lines)
  assert(parsed.head.change_id == "muvqvxnn", "change_id: " .. parsed.head.change_id)
  assert(parsed.head.commit_id == "7809cff3", "commit_id: " .. parsed.head.commit_id)
  assert(parsed.parent.change_id == "tvonrrpo")
  assert(parsed.parent.bookmarks[1] == "main", "bookmark: " .. vim.inspect(parsed.parent.bookmarks))
  assert(parsed.parent.description == "initial commit")

  local files = status.parse_diff_summary({
    "M hello.txt",
    "A src.lua",
  }, "/tmp/test")
  assert(#files == 2)
  assert(files[1].mode == "M")
  assert(files[1].name == "hello.txt")
  assert(files[2].mode == "A")
end)
print(ok and "PASS" or "FAIL", "Status parser:", err or "parses status output")

-- Test 5: Bookmark parser
ok, err = pcall(function()
  local bookmark = require("neojj.lib.jj.bookmark")
  local items = bookmark.parse_list({
    "main: tvonrrpo 63990385 initial commit",
    "  @git: tvonrrpo 63990385 initial commit",
    "feature: muvqvxnn 7809cff3 wip",
  })
  assert(#items == 3, "Expected 3 items, got " .. #items)
  assert(items[1].name == "main")
  assert(items[1].remote == nil)
  assert(items[2].name == "main")
  assert(items[2].remote == "git")
  assert(items[3].name == "feature")
end)
print(ok and "PASS" or "FAIL", "Bookmark parser:", err or "parses bookmark list")

-- Test 6: Diff summary parser
ok, err = pcall(function()
  local status = require("neojj.lib.jj.status")
  local files = status.parse_diff_summary({
    "M lua/neojj/lib/jj/cli.lua",
    "A lua/neojj/lib/jj/status.lua",
    "D old_file.lua",
  }, "/workspace")
  assert(#files == 3)
  assert(files[1].mode == "M")
  assert(files[2].mode == "A")
  assert(files[3].mode == "D")
  assert(files[3].absolute_path == "/workspace/old_file.lua")
end)
print(ok and "PASS" or "FAIL", "Diff summary parser:", err or "parses diff summary")

-- Test 7: Log JSON to entry conversion
ok, err = pcall(function()
  local log = require("neojj.lib.jj.log")
  local entry = log.json_to_entry({
    change_id = "muvqvxnnyrwstlmspzqvvqzmqstxmzwq",
    commit_id = "7809cff3fa826599726c858a8c387ddc46fb7a72",
    description = "add feature\n",
    author = {
      name = "Test User",
      email = "test@example.com",
      timestamp = "2026-03-07T02:38:46-05:00",
    },
  })
  assert(entry.change_id == "muvqvxnnyrwstlmspzqvvqzmqstxmzwq")
  assert(entry.description == "add feature")  -- trailing newline stripped
  assert(entry.author_name == "Test User")
end)
print(ok and "PASS" or "FAIL", "Log entry conversion:", err or "converts JSON to entry")

print("\nDone!")
vim.cmd("qa!")
```

**Step 2: Run the test**

```bash
nvim --headless -u NONE -l tests/jj_backend_test.lua 2>&1
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add tests/jj_backend_test.lua
git commit -m "test(jj): add integration tests for jj backend parsers"
```

---

### Task 10: Update Phase 1 checklist in plan

**Files:**
- Modify: `docs/plans/2026-03-07-neojj-port-plan.md`

**Step 1:** Mark all Phase 1 items as complete.

**Step 2: Commit**

```bash
git add docs/plans/2026-03-07-neojj-port-plan.md
git commit -m "docs: mark Phase 1 complete in plan"
```
