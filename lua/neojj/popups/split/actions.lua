local M = {}
local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")

function M.split_current(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.split
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call { pty = true }
  if result and result.code == 0 then
    notification.info("Split change", { dismiss = true })
  else
    notification.warn("Split failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.split_revision(popup)
  local options = picker_cache.get_all_revisions()
  local sel = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Split revision" }
  local rev = picker_cache.parse_selection(sel)
  if not rev then return end

  local args = popup:get_arguments()
  local builder = jj.cli.split.revision(rev)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call { pty = true }
  if result and result.code == 0 then
    notification.info("Split " .. rev, { dismiss = true })
  else
    notification.warn("Split failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
