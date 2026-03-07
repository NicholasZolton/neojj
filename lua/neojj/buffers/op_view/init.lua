local Buffer = require("neojj.lib.buffer")
local ui = require("neojj.buffers.op_view.ui")
local config = require("neojj.config")
local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")

---@class OpViewBuffer
---@field ops table[] Parsed operation entries
---@field buffer Buffer
local M = {}
M.__index = M

---Parse `jj op log --no-graph` output into operation entries
---Uses a template that outputs structured data.
---@param limit? number
---@return table[] ops
local function fetch_ops(limit)
  limit = limit or 50

  -- Use a template to get structured output
  local tpl = 'id.short(12) ++ "\\t" ++ self.time().start() ++ "\\t" ++ description ++ "\\n"'
  local result = jj.cli.op_log.no_graph.limit(limit).template(tpl).call { hidden = true, trim = true }

  local ops = {}
  if result and result.code == 0 and result.stdout then
    for i, line in ipairs(result.stdout) do
      if line ~= "" then
        local id, time, description = line:match("^(%S+)\t([^\t]*)\t(.*)$")
        if id then
          table.insert(ops, {
            id = id,
            time = time or "",
            description = description or "",
            tags = "",
            current = (i == 1), -- First operation is the current one
          })
        else
          -- Fallback: treat as plain text line
          table.insert(ops, {
            id = string.sub(line, 1, 12),
            time = "",
            description = line,
            tags = "",
            current = (i == 1),
          })
        end
      end
    end
  end

  return ops
end

---Create a new OpViewBuffer
---@return OpViewBuffer
function M.new()
  local instance = {
    ops = fetch_ops(),
    buffer = nil,
  }

  setmetatable(instance, M)
  return instance
end

---Close the buffer
function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end

  M.instance = nil
end

---@return boolean
function M.is_open()
  return (M.instance and M.instance.buffer and M.instance.buffer:is_visible()) == true
end

---Open the operations view
function M:open()
  if M.is_open() then
    M.instance.buffer:focus()
    return
  end

  M.instance = self

  local status_maps = config.get_reversed_status_maps()

  self.buffer = Buffer.create {
    name = "NeoJJOpView",
    filetype = "NeoJJOpView",
    kind = config.values.log_view and config.values.log_view.kind or "tab",
    context_highlight = false,
    status_column = not config.values.disable_signs and "" or nil,
    mappings = {
      n = {
        ["u"] = function()
          local result = jj.cli.undo.call()
          if result and result.code == 0 then
            notification.info("Undo successful")
            -- Refresh the ops list
            self.ops = fetch_ops()
            self.buffer.ui:render(unpack(ui.View(self.ops)))
          else
            notification.error("Undo failed")
          end
        end,
        ["R"] = function()
          -- Get the operation under cursor
          local c = self.buffer.ui:get_component_under_cursor(function(c)
            return c.options.item ~= nil and c.options.item.id ~= nil
          end)

          if not c then
            notification.warn("No operation under cursor")
            return
          end

          local op_id = c.options.item.id
          local result = jj.cli.op_restore.args(op_id).call()
          if result and result.code == 0 then
            notification.info("Restored to operation " .. op_id)
            -- Refresh the ops list
            self.ops = fetch_ops()
            self.buffer.ui:render(unpack(ui.View(self.ops)))
          else
            notification.error("Restore failed")
          end
        end,
        ["q"] = function()
          self:close()
        end,
        ["<esc>"] = function()
          self:close()
        end,
        [status_maps["Close"]] = function()
          self:close()
        end,
        ["r"] = function()
          -- Refresh
          self.ops = fetch_ops()
          self.buffer.ui:render(unpack(ui.View(self.ops)))
        end,
      },
    },
    render = function()
      return ui.View(self.ops)
    end,
    after = function(buffer)
      buffer:move_cursor(4) -- Skip header lines
    end,
  }
end

return M
