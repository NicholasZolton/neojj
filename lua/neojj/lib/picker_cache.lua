local M = {}

local _cache = { revisions = nil, _time = 0 }
local CACHE_TTL = 10 -- seconds

local function invalidate_stale()
  if vim.uv.now() - _cache._time > CACHE_TTL * 1000 then
    _cache.revisions = nil
  end
end

---@return { text: string, prefix_len: integer }[]
function M.get_all_revisions()
  invalidate_stale()
  if _cache.revisions then
    return _cache.revisions
  end

  local log = require("neojj.lib.jj.log")
  local items = log.list("all()")
  local entries = {}
  for _, item in ipairs(items) do
    local short_id = (item.change_id or ""):sub(1, 8)
    local prefix_len = item.shortest_prefix and #item.shortest_prefix or #short_id
    local label = short_id
    if item.description and item.description ~= "" then
      local first_line = vim.split(item.description, "\n")[1]
      label = label .. " " .. first_line
    end
    if item.bookmarks and #item.bookmarks > 0 then
      label = label .. " [" .. table.concat(item.bookmarks, ", ") .. "]"
    end
    table.insert(entries, { text = label, prefix_len = prefix_len })
  end

  _cache.revisions = entries
  _cache._time = vim.uv.now()
  return entries
end

--- Invalidate everything
function M.invalidate()
  _cache.revisions = nil
end

--- Get local bookmark names (no change_id or description, just names)
---@return string[]
function M.get_local_bookmark_names()
  local jj = require("neojj.lib.jj")
  local items = jj.repo.state.bookmarks.items
  local names = {}
  for _, item in ipairs(items) do
    if not item.remote or item.remote == "" then
      table.insert(names, item.name)
    end
  end
  return names
end

--- Get local tags from repository state.
---@return NeojjTagItem[]
function M.get_local_tags()
  local jj = require("neojj.lib.jj")
  return jj.repo.state.tags.items
end

--- Get local tag names.
---@return string[]
function M.get_local_tag_names()
  local names = {}
  for _, item in ipairs(M.get_local_tags()) do
    table.insert(names, item.name)
  end
  return names
end

--- Get remote bookmark names formatted as "name@remote"
---@return string[]
function M.get_remote_bookmark_names()
  local jj = require("neojj.lib.jj")
  local items = jj.repo.state.bookmarks.items
  local names = {}
  for _, item in ipairs(items) do
    if item.remote and item.remote ~= "" then
      table.insert(names, item.name .. "@" .. item.remote)
    end
  end
  return names
end

--- Get local bookmarks formatted as picker labels:
---   "<name> <change_id_short8> <description_first_line>"
--- Reads live from jj.repo.state.bookmarks.items (no caching).
---@return string[]
function M.get_local_bookmarks_with_labels()
  local jj = require("neojj.lib.jj")
  local items = jj.repo.state.bookmarks.items
  local entries = {}
  for _, item in ipairs(items) do
    if not item.remote then
      local label = item.name
      if item.change_id then
        label = label .. " " .. (item.change_id or ""):sub(1, 8)
      end
      if item.description and item.description ~= "" then
        label = label .. " " .. vim.split(item.description, "\n")[1]
      end
      table.insert(entries, label)
    end
  end
  return entries
end

--- Extract the first whitespace-delimited token from a picker selection.
--- Works for both revision entries ("change_id description") and bookmark entries ("name change_id desc").
--- Handles both plain string selections and structured table entries.
---@param selection string|{ text: string }|nil
---@return string?
function M.parse_selection(selection)
  if not selection then
    return nil
  end
  local text = type(selection) == "table" and selection.text or selection --[[@as string]]
  return text:match("^(%S+)")
end

--- Extract a human-readable error message from a command result's stderr.
---@param result table?
---@return string
function M.error_msg(result)
  local err = result and result.stderr or {}
  return type(err) == "table" and table.concat(err, "\n") or tostring(err)
end

--- Filter out internal jj bookmark names (e.g. @git tracking refs) from a list
---@param bookmarks string[]
---@return string[]
function M.filter_bookmarks(bookmarks)
  local filtered = {}
  for _, bm in ipairs(bookmarks) do
    if not bm:match("@git$") then
      table.insert(filtered, bm)
    end
  end
  return filtered
end

return M
