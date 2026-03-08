local M = {}

local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")


function M.squash(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.squash
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Squashed into parent", { dismiss = true })
  else
    notification.warn("Squash failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.squash_into(popup)
  local options = picker_cache.get_all_revisions()
  if #options == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Squash into" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.squash.into(rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Squashed into " .. rev, { dismiss = true })
  else
    notification.warn("Squash failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.squash_revision(popup)
  local options = picker_cache.get_all_revisions()
  if #options == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Squash revision into its parent" }
  local rev = picker_cache.parse_selection(selection)
  if not rev then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.squash.revision(rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Squashed " .. rev .. " into its parent", { dismiss = true })
  else
    notification.warn("Squash failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.squash_range(popup)
  local options = picker_cache.get_all_revisions()
  if #options == 0 then
    notification.warn("No revisions found", { dismiss = true })
    return
  end

  local from_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Squash range from", refocus_status = false }
  local from_rev = picker_cache.parse_selection(from_sel)
  if not from_rev then
    return
  end

  local to_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Squash range to", refocus_status = false }
  local to_rev = picker_cache.parse_selection(to_sel)
  if not to_rev then
    return
  end

  local into_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Squash into", refocus_status = false }
  local into_rev = picker_cache.parse_selection(into_sel)
  if not into_rev then
    return
  end

  local args = popup:get_arguments()
  local range = from_rev .. "::" .. to_rev
  local builder = jj.cli.squash.from(range).into(into_rev)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Squashed " .. range .. " into " .. into_rev, { dismiss = true })
  else
    notification.warn("Squash failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.absorb(_popup)
  local result = jj.cli.absorb.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Absorbed changes into prior commits", { dismiss = true })
  else
    notification.warn("Absorb failed", { dismiss = true })
  end
end

return M
