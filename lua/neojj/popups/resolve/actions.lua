local M = {}
local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")

local function error_msg(result)
  local err = result and result.stderr or {}
  return type(err) == "table" and table.concat(err, "\n") or tostring(err)
end

function M.resolve(popup)
  -- Select a conflicted file if there are multiple
  local conflicts = jj.repo.state.conflicts.items
  if #conflicts == 0 then
    notification.info("No conflicts to resolve")
    return
  end

  local file
  if #conflicts == 1 then
    file = conflicts[1].name
  else
    local names = {}
    for _, c in ipairs(conflicts) do
      table.insert(names, c.name)
    end
    file = FuzzyFinderBuffer.new(names):open_async { prompt_prefix = "Resolve file" }
    if not file then return end
  end

  local args = popup:get_arguments()
  local builder = jj.cli.resolve.args(file)
  if #args > 0 then builder = builder.args(unpack(args)) end
  local result = builder.call { pty = true }
  if result and result.code == 0 then
    notification.info("Resolved " .. file, { dismiss = true })
  else
    notification.warn("Resolve failed: " .. error_msg(result), { dismiss = true })
  end
end

function M.list(_popup)
  local result = jj.cli.resolve.list.call { hidden = true, trim = true }
  if result and result.code == 0 then
    local msg = table.concat(result.stdout, "\n")
    if msg == "" then
      notification.info("No conflicts")
    else
      notification.info("Conflicts:\n" .. msg)
    end
  else
    notification.info("No conflicts to resolve")
  end
end

return M
