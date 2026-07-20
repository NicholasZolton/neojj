local M = {}
local util = require("tests.util.util")

---@class JjPrepareOpts
---@field colocated boolean|nil  Create a colocated jj+git repo (default: false)
---@field cd boolean|nil         chdir into the workspace (default: true)
---@field auto_track boolean|nil Configure repo snapshot.auto-track (default: true)

---Create a fresh jj workspace with some committed history.
---@param opts JjPrepareOpts|nil
---@return string working_dir Absolute path to the workspace root
function M.prepare_repository(opts)
  opts = opts or {}
  local working_dir = util.create_temp_dir(opts.colocated and "jj-colocated" or "jj-noncolocated")

  if opts.cd ~= false then
    vim.api.nvim_set_current_dir(working_dir)
  end

  -- jj 0.40+ defaults to colocated. Explicitly force the desired mode so
  -- tests are stable regardless of user config.
  local init_cmd = {
    "jj",
    "--config=git.colocate=" .. tostring(opts.colocated and true or false),
    "git",
    "init",
    working_dir,
  }
  util.system(init_cmd)

  -- Configure identity at the jj layer so both colocated and non-colocated
  -- repos accept commits (non-colocated has no `.git` to run `git config` on).
  util.system {
    "jj",
    "--repository",
    working_dir,
    "config",
    "set",
    "--repo",
    "user.email",
    "test@neojj-test.test",
  }
  util.system { "jj", "--repository", working_dir, "config", "set", "--repo", "user.name", "NeoJJ Test" }
  local auto_track = opts.auto_track ~= false and "all()" or "none()"
  -- Keep file tracking deterministic even when the user's global jj config
  -- would otherwise override the repository's snapshot behavior.
  util.system {
    "jj",
    "--repository",
    working_dir,
    "config",
    "set",
    "--repo",
    "snapshot.auto-track",
    auto_track,
  }

  vim.fn.writefile({ "line 1", "line 2", "line 3" }, working_dir .. "/a.txt")
  vim.fn.writefile({ "hello world" }, working_dir .. "/b.txt")
  vim.fn.writefile({ "untracked content" }, working_dir .. "/untracked.txt")

  util.system { "jj", "--repository", working_dir, "describe", "-m", "initial commit" }
  util.system { "jj", "--repository", working_dir, "new" }
  util.system { "jj", "--repository", working_dir, "bookmark", "create", "main", "-r", "@-" }

  vim.fn.writefile({ "line 1", "line 2 modified", "line 3" }, working_dir .. "/a.txt")

  return working_dir
end

---Add a secondary jj workspace pointed at the given primary.
---@param primary string Primary workspace path
---@param suffix string Suffix for the unique temp dir name
---@return string secondary_dir
function M.add_secondary_workspace(primary, suffix)
  local secondary = util.create_temp_dir("jj-secondary-" .. suffix)
  -- `jj workspace add` requires the destination to not exist or be empty;
  -- `create_temp_dir` returns an empty dir, so this works directly.
  util.system { "jj", "--repository", primary, "workspace", "add", secondary }
  return secondary
end

---@param cb fun(working_dir: string)
function M.in_prepared_repo(cb)
  return function()
    local working_dir = M.prepare_repository()
    cb(working_dir)
  end
end

---@param cmd string[]
---@return string[]
local function exec(cmd)
  local output = vim.fn.system(cmd)
  local lines = output and vim.split(output, "\n") or {}
  return lines
end

function M.get_jj_status()
  return table.concat(exec { "jj", "status" }, "\n")
end

function M.get_jj_log()
  return exec { "jj", "log", "--no-graph", "-T", 'change_id ++ " " ++ description' }
end

function M.get_jj_bookmarks()
  return exec { "jj", "bookmark", "list" }
end

function M.get_change_id()
  local lines = exec { "jj", "log", "--no-graph", "-r", "@", "-T", "change_id" }
  return vim.trim(lines[1] or "")
end

function M.jj_available()
  return vim.fn.executable("jj") == 1
end

M.exec = exec

return M
