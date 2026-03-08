local M = {}

local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")

local function get_local_bookmarks()
  local items = jj.repo.state.bookmarks.items
  local names = {}
  for _, item in ipairs(items) do
    if not item.remote then
      table.insert(names, item.name)
    end
  end
  return names
end

local function get_remote_bookmarks()
  local items = jj.repo.state.bookmarks.items
  local names = {}
  for _, item in ipairs(items) do
    if item.remote then
      table.insert(names, item.name .. "@" .. item.remote)
    end
  end
  return names
end

---Build a list of recent revisions for fuzzy finding
---Format: "change_id description" for display, returns change_id on selection
local function get_recent_revisions()
  local ok, repo = pcall(function() return jj.repo end)
  if not ok or not repo or not repo.state or not repo.state.recent then
    return {}
  end
  local entries = {}
  for _, item in ipairs(repo.state.recent.items) do
    local label = item.change_id
    if item.description and item.description ~= "" then
      local first_line = vim.split(item.description, "\n")[1]
      label = label .. " " .. first_line
    end
    if item.bookmarks and #item.bookmarks > 0 then
      label = label .. " [" .. table.concat(item.bookmarks, ", ") .. "]"
    end
    table.insert(entries, label)
  end
  return entries
end

---Extract change_id from a revision picker entry
local function parse_revision_selection(selection)
  if not selection then
    return nil
  end
  return selection:match("^(%S+)")
end

function M.create(_popup)
  local name = input.get_user_input("Bookmark name")
  if not name or name == "" then
    return
  end

  local result = jj.cli.bookmark_create.args(name).call()
  if result and result.code == 0 then
    notification.info("Created bookmark " .. name, { dismiss = true })
  else
    notification.warn("Failed to create bookmark", { dismiss = true })
  end
end

function M.set(popup)
  local name = input.get_user_input("Bookmark name (create or update)")
  if not name or name == "" then
    return
  end

  local revisions = get_recent_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Set bookmark to revision (empty = @)" }
    target = parse_revision_selection(selection)
  end

  local args = popup:get_arguments()
  local builder = jj.cli.bookmark_set.args(name)
  if target then
    builder = builder.revision(target)
  end
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Set bookmark " .. name .. (target and (" to " .. target) or " to @"), { dismiss = true })
  else
    notification.warn("Failed to set bookmark", { dismiss = true })
  end
end

function M.move(popup)
  local bookmarks = get_local_bookmarks()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Move bookmark", refocus_status = false }
  if not name then
    return
  end

  local revisions = get_recent_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Move '" .. name .. "' to revision (empty = @)" }
    target = parse_revision_selection(selection)
  end

  local args = popup:get_arguments()
  local builder = jj.cli.bookmark_move.args(name)
  if target then
    builder = builder.to(target)
  end
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Moved bookmark " .. name .. (target and (" to " .. target) or " to @"), { dismiss = true })
  else
    notification.warn("Failed to move bookmark", { dismiss = true })
  end
end

function M.rename(_popup)
  local bookmarks = get_local_bookmarks()
  local old_name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Rename bookmark (old name)", refocus_status = false }
  if not old_name then
    return
  end

  local new_name = input.get_user_input("New name for '" .. old_name .. "'")
  if not new_name or new_name == "" then
    return
  end

  local result = jj.cli.bookmark_rename.args(old_name, new_name).call()
  if result and result.code == 0 then
    notification.info("Renamed bookmark " .. old_name .. " to " .. new_name, { dismiss = true })
  else
    notification.warn("Failed to rename bookmark", { dismiss = true })
  end
end

function M.delete(_popup)
  local bookmarks = get_local_bookmarks()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Delete bookmark" }
  if not name then
    return
  end

  if not input.get_permission(("Delete bookmark '%s'?"):format(name)) then
    return
  end

  local result = jj.cli.bookmark_delete.args(name).call()
  if result and result.code == 0 then
    notification.info("Deleted bookmark " .. name, { dismiss = true })
  else
    notification.warn("Failed to delete bookmark", { dismiss = true })
  end
end

function M.forget(_popup)
  local bookmarks = get_local_bookmarks()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Forget bookmark" }
  if not name then
    return
  end

  if not input.get_permission(("Forget bookmark '%s'?"):format(name)) then
    return
  end

  local result = jj.cli.bookmark_forget.args(name).call()
  if result and result.code == 0 then
    notification.info("Forgot bookmark " .. name, { dismiss = true })
  else
    notification.warn("Failed to forget bookmark", { dismiss = true })
  end
end

function M.track(_popup)
  local bookmarks = get_remote_bookmarks()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Track bookmark" }
  if not name then
    return
  end

  local result = jj.cli.bookmark_track.args(name).call()
  if result and result.code == 0 then
    notification.info("Tracking " .. name, { dismiss = true })
  else
    notification.warn("Failed to track bookmark", { dismiss = true })
  end
end

function M.untrack(_popup)
  local bookmarks = get_remote_bookmarks()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Untrack bookmark" }
  if not name then
    return
  end

  local result = jj.cli.bookmark_untrack.args(name).call()
  if result and result.code == 0 then
    notification.info("Untracked " .. name, { dismiss = true })
  else
    notification.warn("Failed to untrack bookmark", { dismiss = true })
  end
end

function M.advance(_popup)
  local revisions = get_recent_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Advance bookmarks to revision (empty = @)" }
    target = parse_revision_selection(selection)
  end

  local builder = jj.cli.bookmark_advance
  if target then
    builder = builder.to(target)
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Advanced bookmarks" .. (target and (" to " .. target) or ""), { dismiss = true })
  else
    notification.warn("Failed to advance bookmarks", { dismiss = true })
  end
end

return M
