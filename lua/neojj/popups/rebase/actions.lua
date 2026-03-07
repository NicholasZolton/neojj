local M = {}
local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")

local function get_recent_change_ids()
  local items = jj.repo.state.recent.items
  local ids = {}
  for _, item in ipairs(items) do
    local short = string.sub(item.change_id, 1, 12)
    local desc = item.description ~= "" and item.description or "(no description)"
    table.insert(ids, short .. " " .. desc)
  end
  return ids
end

local function extract_change_id(selection)
  if not selection then return nil end
  return selection:match("^(%S+)")
end

function M.source_onto(popup)
  local options = get_recent_change_ids()
  local source_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Rebase source" }
  local source = extract_change_id(source_sel)
  if not source then return end

  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination" }
  local dest = extract_change_id(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.source(source).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Rebased " .. source .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed", { dismiss = true })
  end
end

function M.bookmark_onto(popup)
  -- Select bookmark first
  local bookmarks = {}
  for _, item in ipairs(jj.repo.state.bookmarks.items) do
    if not item.remote then table.insert(bookmarks, item.name) end
  end
  local bm = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Rebase bookmark" }
  if not bm then return end

  local options = get_recent_change_ids()
  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination" }
  local dest = extract_change_id(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.branch(bm).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Rebased bookmark " .. bm .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed", { dismiss = true })
  end
end

function M.revision_onto(popup)
  local options = get_recent_change_ids()
  local rev_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Rebase revision" }
  local rev = extract_change_id(rev_sel)
  if not rev then return end

  local dest_sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "onto destination" }
  local dest = extract_change_id(dest_sel)
  if not dest then return end

  local args = popup:get_arguments()
  local builder = jj.cli.rebase.revision(rev).destination(dest)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Rebased " .. rev .. " onto " .. dest, { dismiss = true })
  else
    notification.warn("Rebase failed", { dismiss = true })
  end
end

return M
