local M = {}

local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

local WORKSPACE_NAME_TEMPLATE = 'self.name() ++ "\\n"'

--- Get the default destination path (parent of current repo root + /)
---@return string
local function default_destination()
  local root = jj.repo.state.worktree_root
  if root then
    return vim.fn.fnamemodify(root, ":h") .. "/"
  end
  return vim.fn.getcwd() .. "/"
end

--- Generate a short random UUID (8 hex chars)
---@return string
local function short_uuid()
  local bytes = {}
  for i = 1, 4 do
    bytes[i] = string.format("%02x", math.random(0, 255))
  end
  return table.concat(bytes)
end

--- Get the worktrees base directory from config
---@return string
local function worktrees_dir()
  local config = require("neojj.config")
  local dir = config.values.workspace_worktrees_directory
  if dir and dir ~= "" then
    return vim.fn.expand(dir)
  end
  return vim.fn.expand("~/.worktrees")
end

--- Resolve the root path of a workspace by name
---@param name string
---@return string|nil
local function resolve_workspace_path(name)
  local result = jj.cli.workspace_root.name(name).call()
  if result and result.code == 0 and result.stdout then
    return vim.trim(table.concat(result.stdout, ""))
  end
  return nil
end

--- Get list of workspace names (excluding current)
---@param include_current? boolean
---@return string[] names, table<string, string> paths
local function get_workspaces(include_current)
  local result = jj.cli.workspace_list.template(WORKSPACE_NAME_TEMPLATE).call()
  if not result or result.code ~= 0 or not result.stdout then
    return {}, {}
  end

  local current_path = resolve_workspace_path("default")
  -- Fall back: if no "default" workspace, use current root
  if not current_path then
    local root = jj.repo.state.worktree_root
    if root then
      current_path = root
    end
  end

  local names = {}
  local paths = {}
  for _, line in ipairs(result.stdout) do
    local name = vim.trim(line)
    if name ~= "" then
      local path = resolve_workspace_path(name)
      local is_current = current_path and path == current_path
      if include_current or not is_current then
        local label = name
        if is_current then
          label = label .. " (current)"
        end
        table.insert(names, label)
        if path then
          paths[name] = path
        end
      end
    end
  end
  return names, paths
end

--- Run workspace_initialize_command and workspace_open_command for a workspace path
---@param path string The workspace directory path
local function run_workspace_hooks(path)
  local config = require("neojj.config")
  local init_cmd = config.values.workspace_initialize_command
  local open_cmd = config.values.workspace_open_command

  if init_cmd and init_cmd ~= "" then
    local cmd = init_cmd:gsub("{path}", path)
    vim.fn.system(cmd)
  end

  if open_cmd and open_cmd ~= "" then
    local cmd = open_cmd:gsub("{path}", path)
    vim.fn.system(cmd)
  end
end

--- Shared logic for creating a workspace
---@param popup table
---@param destination string
---@param revision? string
local function create_workspace(popup, destination, revision)
  local args = popup:get_arguments()
  local builder = jj.cli.workspace_add.args(destination)
  if revision then
    builder = builder.revision(revision)
  end
  if #args > 0 then
    builder = builder.args(unpack(args))
  end

  local result = builder.call()
  if result and result.code == 0 then
    local msg = "Created workspace at " .. destination
    if revision then
      msg = msg .. " at " .. revision
    end
    notification.info(msg, { dismiss = true })
    run_workspace_hooks(destination)
  else
    notification.warn("Failed to create workspace: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.add(popup)
  local destination = input.get_user_input("Workspace destination path", {
    completion = "dir",
    default = default_destination(),
  })
  if not destination or destination == "" then
    return
  end

  destination = vim.fn.fnamemodify(destination, ":p")
  create_workspace(popup, destination)
end

function M.add_at_revision(popup)
  local destination = input.get_user_input("Workspace destination path", {
    completion = "dir",
    default = default_destination(),
  })
  if not destination or destination == "" then
    return
  end

  destination = vim.fn.fnamemodify(destination, ":p")

  local revisions = picker_cache.get_all_revisions()
  local revision = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Base revision (empty = same parent as @)" }
    revision = picker_cache.parse_selection(selection)
  end

  create_workspace(popup, destination, revision)
end

function M.quick_add(popup)
  local base = worktrees_dir()
  vim.fn.mkdir(base, "p")
  local destination = base .. "/" .. short_uuid()
  create_workspace(popup, destination)
end

function M.quick_add_at_revision(popup)
  local revisions = picker_cache.get_all_revisions()
  local revision = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Base revision (empty = same parent as @)" }
    revision = picker_cache.parse_selection(selection)
  end

  local base = worktrees_dir()
  vim.fn.mkdir(base, "p")
  local destination = base .. "/" .. short_uuid()
  create_workspace(popup, destination, revision)
end

function M.forget(_popup)
  local names, _ = get_workspaces(false)
  if #names == 0 then
    notification.warn("No other workspaces to forget", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(names):open_async { prompt_prefix = "Forget workspace" }
  if not selection then
    return
  end

  local name = selection:match("^(%S+)")
  if not name then
    return
  end

  if not input.get_permission(("Forget workspace '%s'? (files stay on disk)"):format(name)) then
    return
  end

  local result = jj.cli.workspace_forget.args(name).call()
  if result and result.code == 0 then
    notification.info("Forgot workspace " .. name, { dismiss = true })
  else
    notification.warn("Failed to forget workspace: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.delete(_popup)
  local names, paths = get_workspaces(false)
  if #names == 0 then
    notification.warn("No other workspaces to delete", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(names):open_async { prompt_prefix = "Delete workspace (forget + rm)" }
  if not selection then
    return
  end

  local name = selection:match("^(%S+)")
  if not name or not paths[name] then
    return
  end

  local path = paths[name]
  if not input.get_permission(("Delete workspace '%s' at %s?"):format(name, path)) then
    return
  end

  local result = jj.cli.workspace_forget.args(name).call()
  if not result or result.code ~= 0 then
    notification.warn("Failed to forget workspace: " .. picker_cache.error_msg(result), { dismiss = true })
    return
  end

  -- Remove the directory
  local rm_result = vim.fn.delete(path, "rf")
  if rm_result == 0 then
    notification.info("Deleted workspace " .. name .. " (" .. path .. ")", { dismiss = true })
  else
    notification.warn("Forgot workspace but failed to delete directory: " .. path, { dismiss = true })
  end
end

function M.list(_popup)
  local names, paths = get_workspaces(true)
  if #names == 0 then
    notification.info("No workspaces found", { dismiss = true })
    return
  end

  -- Build display with paths
  local entries = {}
  for _, label in ipairs(names) do
    local name = label:match("^(%S+)")
    local path = paths[name] or ""
    table.insert(entries, label .. "  " .. path)
  end

  FuzzyFinderBuffer.new(entries):open_async { prompt_prefix = "Workspaces (select to open)" }
end

function M.rename(_popup)
  local new_name = input.get_user_input("New workspace name")
  if not new_name or new_name == "" then
    return
  end

  local result = jj.cli.workspace_rename.args(new_name).call()
  if result and result.code == 0 then
    notification.info("Renamed workspace to " .. new_name, { dismiss = true })
  else
    notification.warn("Failed to rename workspace: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.update_stale(_popup)
  local result = jj.cli.workspace_update_stale.call()
  if result and result.code == 0 then
    notification.info("Workspace updated", { dismiss = true })
  else
    notification.warn("Failed to update workspace: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.root(_popup)
  local result = jj.cli.workspace_root.call()
  if result and result.code == 0 and result.stdout then
    local root = vim.trim(table.concat(result.stdout, ""))
    notification.info("Workspace root: " .. root, { dismiss = true })
  else
    notification.warn("Failed to get workspace root: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
