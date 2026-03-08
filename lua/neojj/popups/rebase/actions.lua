local M = {}
local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

function M.source_onto(popup)
  local options = picker_cache.get_all_revisions()
  local source_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Rebase source", refocus_status = false }
  local source = picker_cache.parse_selection(source_sel)
  if not source then return end

  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination", refocus_status = false }
  local dest = picker_cache.parse_selection(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.source(source).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Rebased " .. source .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.bookmark_onto(popup)
  local bookmarks = picker_cache.get_all_bookmarks()
  local bm_sel = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Rebase bookmark", refocus_status = false }
  if not bm_sel then return end
  local bm = picker_cache.parse_selection(bm_sel)
  if not bm then return end

  local options = picker_cache.get_all_revisions()
  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination", refocus_status = false }
  local dest = picker_cache.parse_selection(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.branch(bm).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Rebased bookmark " .. bm .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.revision_onto(popup)
  local options = picker_cache.get_all_revisions()
  local rev_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Rebase revision", refocus_status = false }
  local rev = picker_cache.parse_selection(rev_sel)
  if not rev then return end

  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination", refocus_status = false }
  local dest = picker_cache.parse_selection(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.revision(rev).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Rebased " .. rev .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.here_onto(popup)
  local options = picker_cache.get_all_revisions()
  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Rebase @ onto" }
  local dest = picker_cache.parse_selection(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.source("@").destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Rebased @ onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

local function fetch_and_rebase(popup, mode_flag, mode_value, desc)
  notification.info("Fetching from remote...", { dismiss = true })
  local fetch_result = jj.cli.git_fetch.call()
  if not fetch_result or fetch_result.code ~= 0 then
    notification.warn("Fetch failed: " .. picker_cache.error_msg(fetch_result), { dismiss = true })
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase[mode_flag](mode_value).destination("trunk()")
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    picker_cache.invalidate()
    notification.info(desc, { dismiss = true })
  else
    notification.warn("Rebase onto trunk failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

--- Fetch + rebase current change onto trunk (jj rebase -s @ -d trunk())
function M.current_onto_trunk(popup)
  fetch_and_rebase(popup, "source", "@", "Rebased @ onto trunk")
end

--- Fetch + rebase whole stack onto trunk (jj rebase -b @ -d trunk())
function M.stack_onto_trunk(popup)
  fetch_and_rebase(popup, "branch", "@", "Rebased stack onto trunk")
end

function M.parallelize(_popup)
  local options = picker_cache.get_all_revisions()
  local sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Parallelize from" }
  local change_id = picker_cache.parse_selection(sel)
  if not change_id then return end

  local result = jj.cli.parallelize.args(change_id .. "::@").call()
  if result and result.code == 0 then
    picker_cache.invalidate_revisions()
    notification.info("Parallelized changes", { dismiss = true })
  else
    notification.warn("Parallelize failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
