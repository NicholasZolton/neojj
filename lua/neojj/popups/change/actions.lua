local M = {}

local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

function M.new_change(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.new
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Created new change", { dismiss = true })
  else
    notification.warn("Failed to create new change", { dismiss = true })
  end
end

function M.new_on_revisions(popup)
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
    notification.info("Created new change on " .. rev, { dismiss = true })
  else
    notification.warn("Failed to create change", { dismiss = true })
  end
end

function M.merge(popup)
  local options = picker_cache.get_all_revisions()
  local first = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "First parent", refocus_status = false }
  local rev1 = picker_cache.parse_selection(first)
  if not rev1 then
    return
  end

  local second = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Second parent" }
  local rev2 = picker_cache.parse_selection(second)
  if not rev2 then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.new.revisions(rev1, rev2)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Created merge change", { dismiss = true })
  else
    notification.warn("Failed to create merge", { dismiss = true })
  end
end

return M
