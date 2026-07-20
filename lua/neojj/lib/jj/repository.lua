---@class NeojjRepoHead
---@field change_id string Short change ID
---@field commit_id string Short commit ID
---@field description string Change description
---@field bookmarks string[] Bookmarks pointing to this change
---@field empty boolean Whether the change is empty
---@field conflict boolean Whether the change has conflicts
---@field shortest_prefix? string Shortest unique change_id prefix

---@class NeojjRepoParent
---@field change_id string
---@field commit_id string
---@field description string
---@field bookmarks string[]
---@field shortest_prefix? string Shortest unique change_id prefix

---@class NeojjFileItem
---@field name string File path
---@field absolute_path string Full file path
---@field escaped_path string Vim-escaped path
---@field fileset_path string jj fileset-safe path (file: prefixed)
---@field mode string "M", "A", "D", "R", "?" (untracked)
---@field original_name string|nil For renames
---@field diff any|nil Lazy-loaded diff
---@field folded boolean|nil

---@class NeojjConflictItem
---@field name string File path
---@field absolute_path string
---@field escaped_path string
---@field fileset_path string jj fileset-safe path (file: prefixed)

---@class NeojjChangeLogEntry
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
---@field divergent boolean Whether jj reports this commit as part of a divergent change group
---@field change_offset integer|nil 0,1,... offset within a divergent group (set on variant entries)
---@field variants NeojjChangeLogEntry[]|nil Set only on synthesized parent entries; holds the original divergent entries
---@field shortest_prefix string|nil
---@field remote_bookmarks string[]|nil

---@class NeojjBookmarkItem
---@field name string
---@field change_id string
---@field commit_id string
---@field description string
---@field remote string|nil Remote name if tracking bookmark
---@field timestamp string|nil Committer timestamp for sorting
---@field deleted boolean|nil True if bookmark has been deleted locally

---@class NeojjRepoState
---@field worktree_root string
---@field head NeojjRepoHead
---@field parent NeojjRepoParent
---@field files { items: NeojjFileItem[] }
---@field conflicts { items: NeojjConflictItem[] }
---@field recent { items: NeojjChangeLogEntry[] }
---@field bookmarks { items: NeojjBookmarkItem[] }

local M = {}

---@return NeojjRepoState
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

---@class NeojjRepo
---@field state NeojjRepoState
---@field lib table<string, { update: fun(state: NeojjRepoState) }>
---@field worktree_root string
---@field running boolean
---@field callbacks table<string, fun()>
local Repo = {}
Repo.__index = Repo

local instances = {}

---Get or create singleton repo instance for a directory
---@param dir? string
---@return NeojjRepo
function Repo.instance(dir)
  local jj_cli = require("neojj.lib.jj.cli")
  dir = dir or vim.fn.getcwd()
  dir = vim.fn.fnamemodify(dir, ":p")

  if not instances[dir] then
    local root = jj_cli.find_workspace_root(dir)
    if not root then
      error("Not inside a jj workspace: " .. dir)
    end
    instances[dir] = Repo.new(root)
  end

  return instances[dir]
end

---Create a new repo instance
---@param root string Workspace root directory
---@return NeojjRepo
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

---Refresh all state from jj (synchronous).
---@param opts? { callback?: fun(), source?: string }
function Repo:refresh(opts)
  opts = opts or {}

  if opts.callback and opts.source then
    self:register_callback(opts.source, opts.callback)
  end

  -- Status first (triggers jj working copy snapshot)
  if self.lib.status and self.lib.status.update then
    self.lib.status.update(self.state)
  end

  -- Log and bookmark
  if self.lib.log and self.lib.log.update then
    self.lib.log.update(self.state)
  end
  if self.lib.bookmark and self.lib.bookmark.update then
    self.lib.bookmark.update(self.state)
  end

  self:run_callbacks()
end

---Dispatch refresh (runs synchronously, then callbacks update UI).
---Wrapped in vim.schedule to avoid blocking the caller's context.
function Repo:dispatch_refresh(opts)
  vim.schedule(function()
    require("neojj.lib.picker_cache").invalidate()
    self:refresh(opts)
  end)
end

M.instance = Repo.instance
M.Repo = Repo

return M
