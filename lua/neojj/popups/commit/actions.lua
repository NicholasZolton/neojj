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
    autocmd = "NeojjCommitComplete",
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
    notification.warn("Failed to create new change: " .. picker_cache.error_msg(result), { dismiss = true })
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

--- Move bookmarks forward after jj new/commit.
--- Before the operation: @ had some bookmarks, @- had some bookmarks.
--- After the operation: old @ is now @-, old @- is now @~2.
--- We move: old @ bookmarks (now on @-) → new @, old @- bookmarks (now on @~2) → new @-.
---@return string[] moved, string[] failed
local function advance_bookmarks()
  local moved = {}
  local failed = {}

  -- Bookmarks from old @ (now on @-) → move to new @
  local at_bookmarks = get_local_bookmarks_at("@-")
  for _, name in ipairs(at_bookmarks) do
    local r = jj.cli.bookmark_set.args(name).revision("@").call()
    if r and r.code == 0 then
      table.insert(moved, name .. " → @")
    else
      table.insert(failed, name .. ": " .. picker_cache.error_msg(r))
    end
  end

  -- Bookmarks from old @- (now on @--) → move to new @-
  local parent_bookmarks = get_local_bookmarks_at("@--")
  for _, name in ipairs(parent_bookmarks) do
    local r = jj.cli.bookmark_set.args(name).revision("@-").call()
    if r and r.code == 0 then
      table.insert(moved, name .. " → @-")
    else
      table.insert(failed, name .. ": " .. picker_cache.error_msg(r))
    end
  end

  return moved, failed
end

function M.new_change_on(popup)
  local options = picker_cache.get_all_revisions()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "New change on" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.revisions(rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Created new change on " .. rev, { dismiss = true })
  else
    notification.warn("Failed to create change: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.new_change_on_with_bookmark(popup)
  local options = picker_cache.get_all_revisions()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "New change on" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.revisions(rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if not result or result.code ~= 0 then
    notification.warn("Failed to create change: " .. picker_cache.error_msg(result), { dismiss = true })
    return
  end

  local moved, failed = advance_bookmarks()
  picker_cache.invalidate_revisions()
  if #failed > 0 then
    notification.warn("Failed to move bookmarks: " .. table.concat(failed, "; "), { dismiss = true })
  elseif #moved > 0 then
    notification.info("Created new change on " .. rev .. ", moved: " .. table.concat(moved, ", "), { dismiss = true })
  else
    notification.info("Created new change on " .. rev .. " (no bookmarks to move)", { dismiss = true })
  end
end

function M.new_change_on_bookmark(popup)
  local options = picker_cache.get_all_bookmarks()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "New change on bookmark" }
  local bookmark = picker_cache.parse_selection(selection)
  if not bookmark then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.revisions(bookmark)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Created new change on " .. bookmark, { dismiss = true })
  else
    notification.warn("Failed to create change: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.new_change_on_bookmark_with_bookmark(popup)
  local options = picker_cache.get_all_bookmarks()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "New change on bookmark" }
  local bookmark = picker_cache.parse_selection(selection)
  if not bookmark then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.revisions(bookmark)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if not result or result.code ~= 0 then
    notification.warn("Failed to create change: " .. picker_cache.error_msg(result), { dismiss = true })
    return
  end

  local moved, failed = advance_bookmarks()
  picker_cache.invalidate_revisions()
  if #failed > 0 then
    notification.warn("Failed to move bookmarks: " .. table.concat(failed, "; "), { dismiss = true })
  elseif #moved > 0 then
    notification.info("Created new change on " .. bookmark .. ", moved: " .. table.concat(moved, ", "), { dismiss = true })
  else
    notification.info("Created new change on " .. bookmark .. " (no bookmarks to move)", { dismiss = true })
  end
end

function M.new_change_before(popup)
  local options = picker_cache.get_all_revisions()
  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "New change before" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.insert_before.revisions(rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Created new change before " .. rev, { dismiss = true })
  else
    notification.warn("Failed to create change: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.new_change_with_bookmark(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.new
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if not result or result.code ~= 0 then
    notification.warn("Failed to create new change: " .. picker_cache.error_msg(result), { dismiss = true })
    return
  end

  local moved, failed = advance_bookmarks()
  picker_cache.invalidate_revisions()
  if #failed > 0 then
    notification.warn("Failed to move bookmarks: " .. table.concat(failed, "; "), { dismiss = true })
  elseif #moved > 0 then
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
    autocmd = "NeojjCommitComplete",
    msg = {
      success = "Committed",
      fail = "Commit aborted",
    },
    show_diff = true,
    interactive = true,
  })

  if code == 0 then
    local moved, failed = advance_bookmarks()
    picker_cache.invalidate_revisions()
    if #failed > 0 then
      notification.warn("Failed to move bookmarks: " .. table.concat(failed, "; "), { dismiss = true })
    elseif #moved > 0 then
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
    autocmd = "NeojjDescribeComplete",
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

  local change_id = picker_cache.parse_selection(selection)
  if not change_id then
    return
  end

  local result = jj.cli.edit.args(change_id).call()
  if result and result.code == 0 then
    notification.info("Now editing " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to edit change: " .. picker_cache.error_msg(result), { dismiss = true })
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

  local bookmark_name = picker_cache.parse_selection(selection)
  if not bookmark_name then
    return
  end

  local result = jj.cli.edit.args(bookmark_name).call()
  if result and result.code == 0 then
    notification.info("Now editing " .. bookmark_name, { dismiss = true })
  else
    notification.warn("Failed to edit bookmark: " .. picker_cache.error_msg(result), { dismiss = true })
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

  local change_id = picker_cache.parse_selection(selection)
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
    notification.warn("Failed to abandon change: " .. picker_cache.error_msg(result), { dismiss = true })
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

  local change_id = picker_cache.parse_selection(selection)
  if not change_id then
    return
  end

  local result = jj.cli.duplicate.args(change_id).call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Duplicated " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to duplicate change: " .. picker_cache.error_msg(result), { dismiss = true })
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

  local change_id = picker_cache.parse_selection(selection)
  if not change_id then
    return
  end

  local result = jj.cli.revert.args(change_id).call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Reverted " .. change_id, { dismiss = true })
  else
    notification.warn("Failed to revert change: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
