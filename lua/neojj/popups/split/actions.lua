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

function M.split_current(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.split
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call { pty = true }
  if result and result.code == 0 then
    notification.info("Split change", { dismiss = true })
  else
    notification.warn("Split failed", { dismiss = true })
  end
end

function M.split_revision(popup)
  local options = get_recent_change_ids()
  local sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Split revision" }
  local rev = extract_change_id(sel)
  if not rev then return end

  local args = popup:get_arguments()
  local builder = jj.cli.split.revision(rev)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call { pty = true }
  if result and result.code == 0 then
    notification.info("Split " .. rev, { dismiss = true })
  else
    notification.warn("Split failed", { dismiss = true })
  end
end

return M
