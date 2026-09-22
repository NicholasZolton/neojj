local M = {}

local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")
local Process = require("neojj.process")
local runner = require("neojj.runner")
local jj_backend = require("neojj.integrations.jj_backend")
local Watcher = require("neojj.watcher")

---@param result table?
---@return string
local function push_error_msg(result)
  local stderr = picker_cache.error_msg(result)
  if
    stderr:match("not a descendant")
    or stderr:match("unexpectedly moved")
    or stderr:match("was updated")
  then
    return "Remote has changed — fetch first, then retry"
  end
  return stderr
end

--- Extract jj `Warning:` blocks (and their `Hint:`/indented continuations) from stderr.
--- Returns the joined block text when at least one `Warning:` line is present, otherwise nil.
--- jj emits all warnings via a centralized `Warning: ` prefix helper, so prefix matching is reliable.
---@param stderr string[]?
---@return string?
local function extract_warnings(stderr)
  if not stderr or #stderr == 0 then
    return nil
  end
  local lines = {}
  local in_block = false
  local saw_warning = false
  for _, line in ipairs(stderr) do
    if line:match("^Warning:") then
      table.insert(lines, line)
      in_block = true
      saw_warning = true
    elseif line:match("^Hint:") then
      table.insert(lines, line)
      in_block = true
    elseif in_block and line:match("^%s") then
      table.insert(lines, line)
    else
      in_block = false
    end
  end
  if not saw_warning then
    return nil
  end
  return table.concat(lines, "\n")
end

---@param lines string[]?
---@return string[]
local function parse_remotes(lines)
  local names = {}
  for _, line in ipairs(lines or {}) do
    local name = line:match("^(%S+)")
    if name then
      table.insert(names, name)
    end
  end
  return names
end

---@param popup PopupData
---@param required? boolean
---@return string|nil, boolean ok
local function maybe_select_remote(popup, required)
  local internal = popup:get_internal_arguments()
  if not required and not internal.remote then
    return nil, true
  end

  local remotes_result = jj.cli.git_remote_list.call { hidden = true, trim = true }
  if not remotes_result or remotes_result.code ~= 0 then
    notification.warn("Push failed: " .. picker_cache.error_msg(remotes_result), { dismiss = true })
    return nil, false
  end

  local remotes = parse_remotes(remotes_result.stdout)
  if #remotes == 0 then
    notification.warn("No remotes configured", { dismiss = true })
    return nil, false
  end

  local remote = FuzzyFinderBuffer.new(remotes):open_async { prompt_prefix = "Push remote" }
  if not remote then
    notification.warn("Push aborted: no remote selected", { dismiss = true })
    return nil, false
  end
  if not vim.tbl_contains(remotes, remote) then
    notification.warn("Push aborted: select a configured remote", { dismiss = true })
    return nil, false
  end

  return remote, true
end

---@param popup PopupData
---@param base_builder table the jj.cli.git_push builder, optionally pre-narrowed (e.g. .bookmark(name))
---@param subject string what is being pushed; "" for plain push, otherwise e.g. "bookmark main"
local function run_push(popup, base_builder, subject)
  local remote, ok = maybe_select_remote(popup)
  if not ok then
    return
  end

  local subject_str = subject ~= "" and (" " .. subject) or ""
  local remote_str = remote and (" to " .. remote) or ""
  notification.info("Pushing" .. subject_str .. remote_str)

  local builder = base_builder
  if remote then
    builder = builder.remote(remote)
  end
  local args = popup:get_arguments()
  if #args > 0 then
    builder = builder.args(unpack(args))
  end

  local result = builder.call()
  if result and result.code == 0 then
    local warnings = extract_warnings(result.stderr)
    if warnings then
      notification.warn(
        "Pushed" .. subject_str .. remote_str .. " with warnings:\n" .. warnings,
        { dismiss = true }
      )
    else
      notification.info("Pushed" .. subject_str .. remote_str, { dismiss = true })
    end
  else
    notification.warn("Push failed: " .. push_error_msg(result), { dismiss = true })
  end
end

function M.push(popup)
  run_push(popup, jj.cli.git_push, "")
end

function M.push_bookmark(popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Push bookmark" }
  if not name then
    return
  end
  run_push(popup, jj.cli.git_push.bookmark(name), "bookmark " .. name)
end

function M.push_change(popup)
  local options = picker_cache.get_all_revisions()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Push change" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end
  run_push(popup, jj.cli.git_push.change(rev), "change " .. rev)
end

function M.push_all(popup)
  run_push(popup, jj.cli.git_push.all, "all bookmarks")
end

---@param result ProcessResult|nil
---@return string
local function git_push_error(result)
  if not result then
    return "command did not return a result"
  end

  local output = {}
  vim.list_extend(output, result.stderr or {})
  vim.list_extend(output, result.stdout or {})
  local message = table.concat(output, "\n")
  return message ~= "" and message or "command failed without output"
end

---@return string|nil workspace
---@return string|nil git_dir
local function colocated_git_context()
  if vim.fn.executable("git") ~= 1 then
    notification.warn("Tag push unavailable: Git executable not found", { dismiss = true })
    return nil, nil
  end

  local workspace = jj.repo.worktree_root
  local git_dir = jj_backend.colocated_git_dir(workspace)
  if not git_dir then
    notification.warn("Tag push requires a colocated jj/Git repository", { dismiss = true })
    return nil, nil
  end

  return workspace, git_dir
end

---@param workspace string
---@param git_dir string
---@param remote string
---@param args string[]
---@param subject string
local function run_git_tag_push(workspace, git_dir, remote, args, subject)
  notification.info("Pushing " .. subject .. " to " .. remote)

  local cmd = { "git", "push" }
  if args[1] == "--tags" then
    table.insert(cmd, "--tags")
  end
  vim.list_extend(cmd, { "--", remote })
  if args[1] ~= "--tags" then
    vim.list_extend(cmd, args)
  end
  local result = runner.call(
    Process.new {
      cmd = cmd,
      cwd = workspace,
      env = { GIT_DIR = git_dir },
      suppress_console = false,
      on_error = function()
        return false
      end,
    },
    {
      await = false,
      hidden = false,
      long = true,
      pty = true,
      trim = false,
      remove_ansi = false,
    }
  )

  if result and result.code == 0 then
    notification.info("Pushed " .. subject .. " to " .. remote, { dismiss = true })
    Watcher.instance(workspace):dispatch_refresh()
  else
    notification.warn("Tag push failed: " .. git_push_error(result), { dismiss = true })
  end
end

function M.push_tag(popup)
  local names = picker_cache.get_local_tag_names()
  local name = FuzzyFinderBuffer.new(names)
    :open_async { prompt_prefix = "Push local tag", refocus_status = false }
  if not name then
    return
  end
  if not vim.tbl_contains(names, name) then
    notification.warn("Tag push aborted: select a local tag", { dismiss = true })
    return
  end

  local workspace, git_dir = colocated_git_context()
  if not workspace or not git_dir then
    return
  end

  local remote, ok = maybe_select_remote(popup, true)
  if not ok or not remote then
    return
  end

  local ref = "refs/tags/" .. name
  run_git_tag_push(workspace, git_dir, remote, { ref .. ":" .. ref }, "tag " .. name)
end

function M.push_all_tags(popup)
  local workspace, git_dir = colocated_git_context()
  if not workspace or not git_dir then
    return
  end

  local remote, ok = maybe_select_remote(popup, true)
  if not ok or not remote then
    return
  end

  if not input.get_permission("Push all local tags to " .. remote .. "?") then
    return
  end

  run_git_tag_push(workspace, git_dir, remote, { "--tags" }, "all local tags")
end

return M
