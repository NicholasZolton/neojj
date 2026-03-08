local M = {}

local _cache = { revisions = nil, bookmarks = nil, _time = 0 }
local CACHE_TTL = 10 -- seconds

local function invalidate_stale()
  if vim.uv.now() - _cache._time > CACHE_TTL * 1000 then
    _cache.revisions = nil
    _cache.bookmarks = nil
  end
end

function M.get_all_revisions()
  invalidate_stale()
  if _cache.revisions then return _cache.revisions end

  local log = require("neojj.lib.jj.log")
  local items = log.list("all()")
  local entries = {}
  for _, item in ipairs(items) do
    local short_id = (item.change_id or ""):sub(1, 8)
    local label = short_id
    if item.description and item.description ~= "" then
      local first_line = vim.split(item.description, "\n")[1]
      label = label .. " " .. first_line
    end
    if item.bookmarks and #item.bookmarks > 0 then
      label = label .. " [" .. table.concat(item.bookmarks, ", ") .. "]"
    end
    table.insert(entries, label)
  end

  _cache.revisions = entries
  _cache._time = vim.uv.now()
  return entries
end

function M.get_all_bookmarks()
  invalidate_stale()
  if _cache.bookmarks then return _cache.bookmarks end

  local bookmark = require("neojj.lib.jj.bookmark")
  local items = bookmark.list()
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

  _cache.bookmarks = entries
  _cache._time = vim.uv.now()
  return entries
end

--- Invalidate everything
function M.invalidate()
  _cache.revisions = nil
  _cache.bookmarks = nil
end

--- Remove a specific revision from the cache by its short change_id prefix
function M.remove_revision(change_id)
  _cache.bookmarks = nil -- bookmark on abandoned commit may be affected
  if not _cache.revisions then return end
  for i, entry in ipairs(_cache.revisions) do
    if entry:sub(1, #change_id) == change_id then
      table.remove(_cache.revisions, i)
      return
    end
  end
end

--- Update description for a revision in cache
function M.update_revision_description(change_id, new_desc)
  if not _cache.revisions then return end
  for i, entry in ipairs(_cache.revisions) do
    if entry:sub(1, #change_id) == change_id then
      local first_line = vim.split(new_desc, "\n")[1]
      _cache.revisions[i] = change_id .. " " .. first_line
      return
    end
  end
end

--- Invalidate revisions and bookmarks (bookmarks can move with rebases, abandons, etc.)
function M.invalidate_revisions()
  _cache.revisions = nil
  _cache.bookmarks = nil
end

--- Invalidate only bookmarks
function M.invalidate_bookmarks()
  _cache.bookmarks = nil
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

--- Extract the first whitespace-delimited token from a picker selection.
--- Works for both revision entries ("change_id description") and bookmark entries ("name change_id desc").
---@param selection string?
---@return string?
function M.parse_selection(selection)
  if not selection then
    return nil
  end
  return selection:match("^(%S+)")
end

return M
