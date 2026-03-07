local a = require("plenary.async")

local M = {}

---@class NeoJJStatusMeta
local meta = {}

---Async-compatible vim.system wrapper that yields in plenary.async coroutines.
---vim.system's callback runs in a fast event context, so we vim.schedule
---back to the main thread before resuming the coroutine.
local jj_system = a.wrap(function(cmd, opts, callback)
  vim.system(cmd, opts, function(result)
    vim.schedule(function()
      callback(result)
    end)
  end)
end, 3)

---Run a jj command asynchronously, returning stdout lines
---@param cmd string[] Command array
---@param cwd string Working directory
---@return string[]|nil lines, number code
local function jj_exec(cmd, cwd)
  local result = jj_system(cmd, { cwd = cwd, text = true })
  if result.code == 0 and result.stdout and result.stdout ~= "" then
    return vim.split(result.stdout, "\n", { trimempty = true }), 0
  end
  return nil, result.code
end

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
  local cwd = state.worktree_root

  -- Get file changes (needs working copy snapshot, no --ignore-working-copy)
  local diff_lines = jj_exec({ "jj", "--no-pager", "--color=never", "diff", "-s" }, cwd)
  if diff_lines then
    state.files.items = M.parse_diff_summary(diff_lines, cwd)

    -- Attach lazy diff loading to each file item
    local jj_diff = require("neojj.lib.jj.diff")
    for _, item in ipairs(state.files.items) do
      jj_diff.build(item)
    end
  end

  -- Get status (working copy + parent info, snapshot already done by diff above)
  local status_lines = jj_exec({ "jj", "--no-pager", "--color=never", "status" }, cwd)
  if status_lines then
    local parsed = M.parse_status_lines(status_lines)
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
    state.conflicts.items = M.parse_conflicts(status_lines, cwd)
  end
end

M.meta = meta

return M
