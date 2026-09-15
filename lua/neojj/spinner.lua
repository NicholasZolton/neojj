local util = require("neojj.lib.util")

-- Pause output while a command prompt is open so messages do not stack in the UI.
local paused = false
vim.api.nvim_create_autocmd("CmdlineEnter", {
  callback = function()
    paused = true
  end,
})
vim.api.nvim_create_autocmd("CmdlineLeave", {
  callback = function()
    paused = false
  end,
})

---@class Spinner
---@field text string
---@field count number
---@field interval number
---@field pattern string[]
---@field timer uv_timer_t
local Spinner = {}
Spinner.__index = Spinner
Spinner.current = nil

---@param status "running"|"success"
---@return table
local function echo_options(status)
  if vim.fn.has("nvim-0.11") == 0 then
    return {}
  end

  return {
    id = "neojj-spinner",
    kind = "progress",
    status = status,
    source = "neojj",
  }
end

---@return Spinner
function Spinner.new(text)
  local instance = {
    text = util.str_truncate(text, vim.v.echospace - 2, "..."),
    interval = 100,
    count = 0,
    timer = nil,
    pattern = {
      "⠋",
      "⠙",
      "⠹",
      "⠸",
      "⠼",
      "⠴",
      "⠦",
      "⠧",
      "⠇",
      "⠏",
    },
  }

  return setmetatable(instance, Spinner)
end

function Spinner:start()
  if Spinner.current then
    Spinner.current:stop()
  end
  Spinner.current = self

  if not self.timer then
    self.timer = assert(vim.uv.new_timer())
    self.timer:start(
      250,
      self.interval,
      vim.schedule_wrap(function()
        if paused then
          return
        end

        self.count = self.count + 1
        local step = self.pattern[(self.count % #self.pattern) + 1]
        vim.api.nvim_echo({ { step .. " " .. self.text, "" } }, false, echo_options("running"))
      end)
    )
  end
end

function Spinner:stop()
  if self.timer then
    local timer = self.timer
    self.timer = nil
    timer:stop()

    vim.api.nvim_echo({ { "", "" } }, false, echo_options("success"))

    if Spinner.current == self then
      Spinner.current = nil
    end

    if not timer:is_closing() then
      timer:close()
    end
  end
end

return Spinner
