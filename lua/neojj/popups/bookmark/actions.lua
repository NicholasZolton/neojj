local M = {}

local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

function M.create(_popup)
  local name = input.get_user_input("Bookmark name")
  if not name or name == "" then
    return
  end

  local result = jj.cli.bookmark_create.args(name).call()
  if result and result.code == 0 then
    notification.info("Created bookmark " .. name, { dismiss = true })
  else
    notification.warn("Failed to create bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.set(popup)
  local name = input.get_user_input("Bookmark name (create or update)")
  if not name or name == "" then
    return
  end

  local revisions = picker_cache.get_all_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Set bookmark to revision (empty = @)" }
    target = picker_cache.parse_selection(selection)
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
    notification.warn("Failed to set bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.move(popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Move bookmark", refocus_status = false }
  if not name then
    return
  end

  local revisions = picker_cache.get_all_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Move '" .. name .. "' to revision (empty = @)" }
    target = picker_cache.parse_selection(selection)
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
    notification.warn("Failed to move bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.move_to_bookmark(popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Move bookmark", refocus_status = false }
  if not name then
    return
  end

  local target = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Move '" .. name .. "' to bookmark" }
  if not target then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.bookmark_move.args(name).to(target)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Moved bookmark " .. name .. " to " .. target, { dismiss = true })
  else
    notification.warn("Failed to move bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.rename(_popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
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
    notification.warn("Failed to rename bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.delete(_popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
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
    notification.warn("Failed to delete bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.forget(_popup)
  local bookmarks = picker_cache.get_local_bookmark_names()
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
    notification.warn("Failed to forget bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.track(_popup)
  local bookmarks = picker_cache.get_remote_bookmark_names()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Track bookmark" }
  if not name then
    return
  end

  local result = jj.cli.bookmark_track.args(name).call()
  if result and result.code == 0 then
    notification.info("Tracking " .. name, { dismiss = true })
  else
    notification.warn("Failed to track bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.untrack(_popup)
  local bookmarks = picker_cache.get_remote_bookmark_names()
  local name = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Untrack bookmark" }
  if not name then
    return
  end

  local result = jj.cli.bookmark_untrack.args(name).call()
  if result and result.code == 0 then
    notification.info("Untracked " .. name, { dismiss = true })
  else
    notification.warn("Failed to untrack bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.advance(_popup)
  local revisions = picker_cache.get_all_revisions()
  local target = nil
  if #revisions > 0 then
    local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Advance bookmarks to revision (empty = @)" }
    target = picker_cache.parse_selection(selection)
  end

  local builder = jj.cli.bookmark_advance
  if target then
    builder = builder.to(target)
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Advanced bookmarks" .. (target and (" to " .. target) or ""), { dismiss = true })
  else
    notification.warn("Failed to advance bookmarks: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
