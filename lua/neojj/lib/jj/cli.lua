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

  local cmd = { "jj", "--no-pager", "--color=never" }

  -- Add --ignore-working-copy for read-only commands
  local readonly_commands = {
    ["log"] = true,
    ["diff"] = true,
    ["show"] = true,
    ["status"] = true,
    ["bookmark list"] = true,
    ["op log"] = true,
    ["file list"] = true,
    ["file annotate"] = true,
    ["git remote list"] = true,
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
    local repo_ok, repo = pcall(function() return jj.repo end)
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
    local command_name = k:gsub("_", " ")
    local cfg = commands[command_name]
    if cfg then
      return new_builder(command_name, cfg)
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
