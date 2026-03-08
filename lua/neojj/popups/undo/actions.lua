local M = {}

local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local picker_cache = require("neojj.lib.picker_cache")

function M.undo(_popup)
  local result = jj.cli.undo.call()
  if result and result.code == 0 then
    picker_cache.invalidate()
    notification.info("Undone", { dismiss = true })
  else
    local err = result and result.stderr or {}
    local msg = type(err) == "table" and table.concat(err, "\n") or tostring(err)
    notification.warn("Undo failed: " .. msg, { dismiss = true })
  end
end

function M.redo(_popup)
  local result = jj.cli.redo.call()
  if result and result.code == 0 then
    picker_cache.invalidate()
    notification.info("Redone", { dismiss = true })
  else
    local err = result and result.stderr or {}
    local msg = type(err) == "table" and table.concat(err, "\n") or tostring(err)
    notification.warn("Redo failed: " .. msg, { dismiss = true })
  end
end

function M.op_restore(_popup)
  local result = jj.cli.op_log.no_graph.call { hidden = true, trim = true }
  if not result or result.code ~= 0 or not result.stdout or #result.stdout == 0 then
    notification.warn("Failed to get operation log", { dismiss = true })
    return
  end

  -- Parse op log into picker entries - each operation is a multi-line block
  local entries = {}
  local current = {}
  for _, line in ipairs(result.stdout) do
    if line:match("^%x") and #current > 0 then
      table.insert(entries, table.concat(current, " "))
      current = {}
    end
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      table.insert(current, trimmed)
    end
  end
  if #current > 0 then
    table.insert(entries, table.concat(current, " "))
  end

  if #entries == 0 then
    notification.warn("No operations found", { dismiss = true })
    return
  end

  local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
  local selection = FuzzyFinderBuffer.new(entries):open_async { prompt_prefix = "Restore to operation" }
  if not selection then
    return
  end

  local op_id = selection:match("^(%x+)")
  if not op_id then
    return
  end

  local restore_result = jj.cli.op_restore.args(op_id).call()
  if restore_result and restore_result.code == 0 then
    picker_cache.invalidate()
    notification.info("Restored to operation " .. op_id, { dismiss = true })
  else
    local err = restore_result and restore_result.stderr or {}
    local msg = type(err) == "table" and table.concat(err, "\n") or tostring(err)
    notification.warn("Restore failed: " .. msg, { dismiss = true })
  end
end

return M
