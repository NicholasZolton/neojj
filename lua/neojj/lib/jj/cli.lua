local Process = require("neojj.process")
local runner = require("neojj.runner")

---@class NeojjCliBuilder
-- Built-in chainable methods
---@field args fun(...: string|number): NeojjCliBuilder
---@field arguments fun(...: string|number): NeojjCliBuilder
---@field files fun(...: string): NeojjCliBuilder
---@field paths fun(...: string): NeojjCliBuilder
---@field input fun(value: string): NeojjCliBuilder
---@field stdin fun(value: string): NeojjCliBuilder
---@field env fun(cfg: table<string, string>): NeojjCliBuilder
---@field in_pty fun(v: boolean): NeojjCliBuilder
---@field call fun(opts?: table): ProcessResult?
---@field to_process fun(opts?: table): Process
-- Flags: setting the property mutates and returns the builder for further chaining.
---@field no_graph NeojjCliBuilder
---@field patch NeojjCliBuilder
---@field summary NeojjCliBuilder
---@field stat NeojjCliBuilder
---@field reversed NeojjCliBuilder
---@field git NeojjCliBuilder
---@field color_words NeojjCliBuilder
---@field types NeojjCliBuilder
---@field name_only NeojjCliBuilder
---@field no_edit NeojjCliBuilder
---@field reset_author NeojjCliBuilder
---@field insert_before NeojjCliBuilder
---@field insert_after NeojjCliBuilder
---@field interactive NeojjCliBuilder
---@field keep_emptied NeojjCliBuilder
---@field use_destination_message NeojjCliBuilder
---@field skip_emptied NeojjCliBuilder
---@field keep_divergent NeojjCliBuilder
---@field simplify_parents NeojjCliBuilder
---@field list NeojjCliBuilder
---@field all_remotes NeojjCliBuilder
---@field allow_backwards NeojjCliBuilder
---@field overwrite_existing NeojjCliBuilder
---@field all NeojjCliBuilder
---@field dry_run NeojjCliBuilder
---@field deleted NeojjCliBuilder
---@field repo NeojjCliBuilder
---@field user NeojjCliBuilder
-- Options: invoking with a value appends the option pair and returns the builder.
---@field template fun(value: string): NeojjCliBuilder
---@field revisions fun(...: string): NeojjCliBuilder
---@field revision fun(value: string): NeojjCliBuilder
---@field limit fun(value: integer|string): NeojjCliBuilder
---@field from fun(value: string): NeojjCliBuilder
---@field to fun(value: string): NeojjCliBuilder
---@field context fun(value: integer|string): NeojjCliBuilder
---@field tool fun(value: string): NeojjCliBuilder
---@field message fun(value: string): NeojjCliBuilder
---@field source fun(value: string): NeojjCliBuilder
---@field branch fun(value: string): NeojjCliBuilder
---@field destination fun(value: string): NeojjCliBuilder
---@field before fun(value: string): NeojjCliBuilder
---@field after fun(value: string): NeojjCliBuilder
---@field what fun(value: string): NeojjCliBuilder
---@field name fun(value: string): NeojjCliBuilder
---@field sparse_patterns fun(value: string): NeojjCliBuilder
---@field into fun(value: string): NeojjCliBuilder
---@field remote fun(value: string): NeojjCliBuilder
---@field bookmark fun(value: string): NeojjCliBuilder
---@field change fun(value: string): NeojjCliBuilder

---@class NeojjCLI
---@field status NeojjCliBuilder
---@field log NeojjCliBuilder
---@field diff NeojjCliBuilder
---@field show NeojjCliBuilder
---@field describe NeojjCliBuilder
---@field new NeojjCliBuilder
---@field commit NeojjCliBuilder
---@field squash NeojjCliBuilder
---@field split NeojjCliBuilder
---@field edit NeojjCliBuilder
---@field abandon NeojjCliBuilder
---@field restore NeojjCliBuilder
---@field rebase NeojjCliBuilder
---@field duplicate NeojjCliBuilder
---@field resolve NeojjCliBuilder
---@field bookmark_list NeojjCliBuilder
---@field bookmark_create NeojjCliBuilder
---@field bookmark_move NeojjCliBuilder
---@field bookmark_delete NeojjCliBuilder
---@field bookmark_forget NeojjCliBuilder
---@field bookmark_track NeojjCliBuilder
---@field bookmark_untrack NeojjCliBuilder
---@field bookmark_rename NeojjCliBuilder
---@field bookmark_set NeojjCliBuilder
---@field bookmark_advance NeojjCliBuilder
---@field git_push NeojjCliBuilder
---@field git_fetch NeojjCliBuilder
---@field git_remote_add NeojjCliBuilder
---@field git_remote_remove NeojjCliBuilder
---@field git_remote_rename NeojjCliBuilder
---@field git_remote_list NeojjCliBuilder
---@field undo NeojjCliBuilder
---@field redo NeojjCliBuilder
---@field op_restore NeojjCliBuilder
---@field op_log NeojjCliBuilder
---@field revert NeojjCliBuilder
---@field diffedit NeojjCliBuilder
---@field file_list NeojjCliBuilder
---@field file_track NeojjCliBuilder
---@field file_untrack NeojjCliBuilder
---@field file_annotate NeojjCliBuilder
---@field file_show NeojjCliBuilder
---@field config_get NeojjCliBuilder
---@field config_set NeojjCliBuilder
---@field config_unset NeojjCliBuilder
---@field workspace_add NeojjCliBuilder
---@field workspace_forget NeojjCliBuilder
---@field workspace_list NeojjCliBuilder
---@field workspace_rename NeojjCliBuilder
---@field workspace_root NeojjCliBuilder
---@field workspace_update_stale NeojjCliBuilder
---@field absorb NeojjCliBuilder
---@field parallelize NeojjCliBuilder
---@field obslog NeojjCliBuilder
---@field find_workspace_root fun(dir?: string): string?
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
        table.insert(state.options, config.options[action])
        table.insert(state.options, tostring(value))
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
  local cmd = M._build_cmd(tbl)
  return table.concat(cmd, " ")
end

-- Create a new builder for a subcommand
local function new_builder(command, config)
  return setmetatable({
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
end

---Build command array from builder state
---@param tbl table Builder instance
---@return string[] command array
function M._build_cmd(tbl)
  local state = rawget(tbl, k_state)
  local command = rawget(tbl, k_command)

  local jj_bin = require("neojj.lib.jj.shell").resolve_jj()
  local cmd = { jj_bin, "--no-pager", "--color=never" }

  -- Add --ignore-working-copy for commands that don't need live working copy state.
  -- NOTE: diff and status are intentionally excluded — they must see the current
  -- working copy, so jj needs to auto-snapshot before running them.
  local readonly_commands = {
    ["log"] = true,
    ["show"] = true,
    ["bookmark list"] = true,
    ["op log"] = true,
    ["file list"] = true,
    ["file annotate"] = true,
    ["file show"] = true,
    ["git remote list"] = true,
    ["workspace list"] = true,
    ["workspace root"] = true,
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
  local cmd = M._build_cmd(tbl)

  -- Try to get workspace root, fall back to cwd
  local cwd
  local ok, jj = pcall(require, "neojj.lib.jj")
  if ok then
    local repo_ok, repo = pcall(function()
      return jj.repo
    end)
    if repo_ok and repo then
      cwd = repo.worktree_root
    end
  end
  cwd = cwd or vim.fn.getcwd()

  return Process.new {
    cmd = cmd,
    cwd = cwd,
    env = state.env,
    input = state.input,
    pty = state.in_pty,
    suppress_console = opts and opts.hidden or false,
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

local commands = {}

local function define_command(name, cfg)
  commands[name] = cfg or {}
end

-- jj status
define_command("status", {})

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
  },
  aliases = {
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
    keep_emptied = "--keep-emptied",
    use_destination_message = "--use-destination-message",
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

-- jj edit
define_command("edit", {})

-- jj abandon
define_command("abandon", {})

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
    keep_divergent = "--keep-divergent",
    simplify_parents = "--simplify-parents",
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
define_command("bookmark track", {
  options = {
    remote = "--remote",
  },
})

-- jj bookmark untrack
define_command("bookmark untrack", {
  options = {
    remote = "--remote",
  },
})

-- jj bookmark rename
define_command("bookmark rename", {
  flags = {
    overwrite_existing = "--overwrite-existing",
  },
})

-- jj bookmark set
define_command("bookmark set", {
  flags = {
    allow_backwards = "--allow-backwards",
  },
  options = {
    revision = "-r",
  },
})

-- jj bookmark advance
define_command("bookmark advance", {
  options = {
    to = "--to",
  },
})

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

-- jj redo
define_command("redo", {})

-- jj op restore
define_command("op restore", {
  options = {
    what = "--what",
  },
})

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

-- jj file track
define_command("file track", {})

-- jj file annotate
define_command("file annotate", {})

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

-- jj workspace add
define_command("workspace add", {
  options = {
    name = "--name",
    revision = "-r",
    message = "-m",
    sparse_patterns = "--sparse-patterns",
  },
})

-- jj workspace forget
define_command("workspace forget", {})

-- jj workspace list
define_command("workspace list", {
  options = {
    template = "-T",
  },
})

-- jj workspace rename
define_command("workspace rename", {})

-- jj workspace root
define_command("workspace root", {
  options = {
    name = "--name",
  },
})

-- jj workspace update-stale
define_command("workspace update-stale", {})

-- jj absorb
define_command("absorb", {
  options = {
    from = "--from",
    into = "--into",
  },
})

-- jj parallelize
define_command("parallelize", {})

-- jj obslog
define_command("obslog", {
  options = {
    revision = "-r",
    limit = "-n",
    template = "-T",
  },
})

-- ============================================================
-- Module metatable: access commands as properties
-- ============================================================

setmetatable(M, {
  __index = function(_, k)
    -- Normalize underscores to spaces for multi-word commands
    -- e.g., M.git_push → "git push", M.bookmark_list → "bookmark list"
    local command_name = k:gsub("_", " ")
    local cfg = commands[command_name]
    if cfg then
      return new_builder(command_name, cfg)
    end

    -- Try joining last two words with hyphen for commands like "workspace update-stale"
    -- e.g., workspace_update_stale → "workspace update stale" → "workspace update-stale"
    local hyphenated = command_name:gsub("(%S+) (%S+)$", "%1-%2")
    if hyphenated ~= command_name then
      cfg = commands[hyphenated]
      if cfg then
        return new_builder(hyphenated, cfg)
      end
    end

    -- Also try exact name (for single-word commands like "log")
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

---@type table<string, string|false>
local workspace_root_cache = {}

---Find workspace root by walking up looking for .jj directory (no subprocess needed)
---@param dir string Starting directory
---@return string|nil root
local function find_jj_root(dir)
  local path = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
  while path and path ~= "" do
    if vim.uv.fs_stat(path .. "/.jj") then
      return path
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
  return nil
end

---Get the workspace root directory
---@param dir? string Directory to check from
---@return string|nil root
function M.find_workspace_root(dir)
  dir = dir or vim.fn.getcwd()
  local key = vim.fn.fnamemodify(dir, ":p")

  if workspace_root_cache[key] ~= nil then
    local cached = workspace_root_cache[key]
    return cached ~= false and cached or nil
  end

  local root = find_jj_root(dir)

  if root then
    workspace_root_cache[key] = root
    local root_key = vim.fn.fnamemodify(root, ":p")
    if root_key ~= key then
      workspace_root_cache[root_key] = root
    end
    return root
  end

  workspace_root_cache[key] = false
  return nil
end

---Check if directory is inside a jj workspace
---@param dir? string Directory to check
---@return boolean
function M.is_inside_workspace(dir)
  return M.find_workspace_root(dir) ~= nil
end

---Clear the workspace root cache (e.g., after init)
function M.clear_cache()
  workspace_root_cache = {}
end

return M
