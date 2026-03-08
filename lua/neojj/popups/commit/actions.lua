local M = {}

local jj = require("neojj.lib.jj")
local client = require("neojj.client")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

function M.commit(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.commit
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  client.wrap(builder, {
    autocmd = "NeoJJCommitComplete",
    msg = {
      success = "Committed",
      fail = "Commit aborted",
    },
    show_diff = true,
    interactive = true,
  })
end

function M.new_change(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.new
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Created new change", { dismiss = true })
  else
    notification.warn("Failed to create new change", { dismiss = true })
  end
end

--- Get local bookmark names pointing at a given revision
---@param rev string revision specifier (e.g. "@")
---@return string[]
local function get_local_bookmarks_at(rev)
  local result = jj.cli.bookmark_list
    .template('if(!self.remote(), self.name() ++ "\\n")')
    .revisions(rev)
    .call()
  if not result or result.code ~= 0 or not result.stdout then
    return {}
  end
  local names = {}
  for _, line in ipairs(result.stdout) do
    local name = vim.trim(line)
    if name ~= "" then
      table.insert(names, name)
    end
  end
  return names
end

--- Move local bookmarks from @- to @ after creating a new change
---@param bookmarks string[]
---@return string[] moved bookmark names
local function move_bookmarks_forward(bookmarks)
  local moved = {}
  for _, name in ipairs(bookmarks) do
    local set_result = jj.cli.bookmark_set.args(name).revision("@").call()
    if set_result and set_result.code == 0 then
      table.insert(moved, name)
    end
  end
  return moved
end

function M.new_change_with_bookmark(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.new
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if not result or result.code ~= 0 then
    notification.warn("Failed to create new change", { dismiss = true })
    return
  end

  -- After jj new: old @ is now @-, new @ is empty working copy
  local bookmarks = get_local_bookmarks_at("@-")
  local moved = move_bookmarks_forward(bookmarks)
  picker_cache.invalidate_revisions()
  if #moved > 0 then
    notification.info("Created new change, moved: " .. table.concat(moved, ", "), { dismiss = true })
  else
    notification.info("Created new change (no bookmarks to move)", { dismiss = true })
  end
end

function M.commit_with_bookmark(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.commit
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local code = client.wrap(builder, {
    autocmd = "NeoJJCommitComplete",
    msg = {
      success = "Committed",
      fail = "Commit aborted",
    },
    show_diff = true,
    interactive = true,
  })

  if code == 0 then
    -- After jj commit: old @ is now @-, new @ is empty working copy
    -- Find bookmarks on @- and move them forward to @
    local bookmarks = get_local_bookmarks_at("@-")
    local moved = move_bookmarks_forward(bookmarks)
    picker_cache.invalidate_revisions()
    if #moved > 0 then
      notification.info("Moved bookmarks: " .. table.concat(moved, ", "), { dismiss = true })
    end
  end
end

function M.describe(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.describe
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  client.wrap(builder, {
    autocmd = "NeoJJDescribeComplete",
    msg = {
      success = "Description updated",
      fail = "Describe failed",
    },
    show_diff = true,
    interactive = true,
  })
end

function M.describe_with_message(popup)
  local msg = input.get_user_input("Describe change")
  if not msg or msg == "" then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.describe.no_edit.message(msg)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Description updated", { dismiss = true })
  else
    notification.warn("Describe failed", { dismiss = true })
  end
end

function M.edit_change(_popup)
  local revisions = picker_cache.get_all_revisions()
  if #revisions == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Edit change" }
  if not selection then
    return
  end

  local change_id = selection:match("^(%S+)")
  if not change_id then
    return
  end

  local result = jj.cli.edit.args(change_id).call()
  if result and result.code == 0 then
    notification.info("Now editing " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to edit change", { dismiss = true })
  end
end

function M.edit_bookmark(_popup)
  local bookmarks = picker_cache.get_all_bookmarks()
  if #bookmarks == 0 then
    notification.warn("No bookmarks found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Edit bookmark" }
  if not selection then
    return
  end

  local bookmark_name = selection:match("^(%S+)")
  if not bookmark_name then
    return
  end

  local result = jj.cli.edit.args(bookmark_name).call()
  if result and result.code == 0 then
    notification.info("Now editing " .. bookmark_name, { dismiss = true })
  else
    notification.warn("Failed to edit bookmark", { dismiss = true })
  end
end

function M.abandon(_popup)
  local revisions = picker_cache.get_all_revisions()
  if #revisions == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Abandon change" }
  if not selection then
    return
  end

  local change_id = selection:match("^(%S+)")
  if not change_id then
    return
  end

  if not input.get_permission("Abandon " .. change_id .. "?") then
    return
  end

  local result = jj.cli.abandon.args(change_id).call()
  if result and result.code == 0 then
    picker_cache.remove_revision(change_id)
    notification.info("Abandoned " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to abandon change", { dismiss = true })
  end
end

function M.duplicate(_popup)
  local revisions = picker_cache.get_all_revisions()
  if #revisions == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Duplicate change" }
  if not selection then
    return
  end

  local change_id = selection:match("^(%S+)")
  if not change_id then
    return
  end

  local result = jj.cli.duplicate.args(change_id).call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Duplicated " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to duplicate change", { dismiss = true })
  end
end

function M.revert(_popup)
  local revisions = picker_cache.get_all_revisions()
  if #revisions == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(revisions):open_async { prompt_prefix = "Revert change" }
  if not selection then
    return
  end

  local change_id = selection:match("^(%S+)")
  if not change_id then
    return
  end

  local result = jj.cli.revert.args(change_id).call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Reverted " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to revert change", { dismiss = true })
  end
end

return M
