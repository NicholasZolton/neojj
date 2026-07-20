---@class NeojjStatus
---@field parse_diff_summary fun(lines: string[], root: string): NeojjFileItem[]
---@field parse_status_files fun(lines: string[], root: string): NeojjFileItem[]
---@field parse_status_lines fun(lines: string[]): NeojjStatusInfo
---@field parse_conflicts fun(lines: string[], root: string): NeojjConflictItem[]
local M = {}

---@class NeojjStatusMeta
local meta = {}

---Run a jj command via the shell module (resolves real binary, bypasses shims)
---@param cmd string[] Command array
---@param cwd string Working directory
---@return string[]|nil lines, number code
local function jj_exec(cmd, cwd)
  local shell = require("neojj.lib.jj.shell")
  return shell.exec(cmd, cwd)
end

---Parse `jj diff --summary` output into file items
---@param lines string[]
---@param root string Workspace root for absolute paths
---@return NeojjFileItem[]
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
        fileset_path = "file:" .. name,
        original_name = nil,
        diff = nil,
        folded = nil,
      })
    end
  end
  return items
end

---Parse changed files from `jj status` output (the "Working copy changes:" section)
---@param lines string[]
---@param root string Workspace root for absolute paths
---@return NeojjFileItem[]
function M.parse_status_files(lines, root)
  local items = {}
  local in_changes = false

  for _, line in ipairs(lines) do
    if line:match("^Working copy changes:") or line:match("^Untracked paths:") then
      in_changes = true
    elseif in_changes then
      local mode, name = line:match("^([%a?])%s+(.+)$")
      if mode and name then
        table.insert(items, {
          name = name,
          mode = mode,
          absolute_path = root .. "/" .. name,
          escaped_path = vim.fn.fnameescape(name),
          fileset_path = "file:" .. name,
          original_name = nil,
          diff = nil,
          folded = nil,
        })
      else
        in_changes = false
      end
    end
  end

  return items
end

---@class NeojjStatusInfo
---@field head NeojjRepoHead
---@field parent NeojjRepoParent

---Parse `jj status` output for working copy and parent info
---@param lines string[]
---@return NeojjStatusInfo
function M.parse_status_lines(lines)
  ---@type NeojjRepoHead
  local head = {
    change_id = "",
    commit_id = "",
    description = "",
    bookmarks = {},
    empty = true,
    conflict = false,
  }
  ---@type NeojjRepoParent
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
        -- Parse bookmarks before the | separator (same format as parent)
        local bookmark_part, desc = rest:match("^(.-)%s*|%s*(.*)$")
        if bookmark_part and #bookmark_part > 0 then
          for bm in bookmark_part:gmatch("%S+") do
            table.insert(head.bookmarks, bm)
          end
          head.description = desc or ""
        else
          head.description = rest or ""
        end
        head.empty = rest ~= nil and rest:match("%(empty%)") ~= nil
        head.conflict = rest ~= nil and rest:match("%(conflict%)") ~= nil
      end
    end

    -- Parent commit (@-): <change_id> <commit_id> [bookmarks |] <description>
    local pc_rest = line:match("^Parent commit%s+%(@%-%)+:%s*(.+)$")
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
---@return NeojjConflictItem[]
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
          fileset_path = "file:" .. name,
        })
      else
        in_conflicts = false
      end
    end
  end

  return conflicts
end

---Update repository state with jj status data
---@param state NeojjRepoState
function meta.update(state)
  local cwd = state.worktree_root

  -- Single jj status call: parses files, head/parent info, and conflicts
  local status_lines = jj_exec({ "jj", "--no-pager", "--color=never", "status" }, cwd)
  if status_lines then
    -- Parse file changes from "Working copy changes:" section
    state.files.items = M.parse_status_files(status_lines, cwd)

    -- Attach lazy diff loading to each file item
    local jj_diff = require("neojj.lib.jj.diff")
    for _, item in ipairs(state.files.items) do
      jj_diff.build(item)
    end

    -- Parse head/parent info
    local picker_cache = require("neojj.lib.picker_cache")
    local parsed = M.parse_status_lines(status_lines)
    state.head.change_id = parsed.head.change_id
    state.head.commit_id = parsed.head.commit_id
    state.head.empty = parsed.head.empty
    state.head.conflict = parsed.head.conflict
    state.head.bookmarks = picker_cache.filter_bookmarks(parsed.head.bookmarks)
    if parsed.head.description ~= "" then
      state.head.description = parsed.head.description
    end
    state.parent.change_id = parsed.parent.change_id
    state.parent.commit_id = parsed.parent.commit_id
    state.parent.description = parsed.parent.description
    state.parent.bookmarks = picker_cache.filter_bookmarks(parsed.parent.bookmarks)

    -- Parse conflicts
    state.conflicts.items = M.parse_conflicts(status_lines, cwd)
  end
end

M.meta = meta

return M
