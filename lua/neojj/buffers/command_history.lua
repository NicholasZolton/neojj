local Buffer = require("neojj.lib.buffer")
local runner = require("neojj.runner")
local Ui = require("neojj.lib.ui")
local util = require("neojj.lib.util")
local status_maps = require("neojj.config").get_reversed_status_maps()

local map = util.map
local filter_map = util.filter_map

local text = Ui.text
local col = Ui.col
local row = Ui.row

local command_masks = {
  vim.pesc(" --no-pager --color=never --ignore-working-copy"),
  vim.pesc(" --no-pager --color=never"),
}

local M = {}

function M:new(state)
  local this = {
    buffer = nil,
    state = state or runner.history,
  }

  setmetatable(this, { __index = M })

  return this
end

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

function M:show()
  if M.is_open() then
    M.instance.buffer:focus()
    return
  end

  M.instance = self

  self.buffer = Buffer.create {
    kind = "popup",
    name = "NeojjCommandHistory",
    filetype = "NeojjCommandHistory",
    mappings = {
      n = {
        [status_maps["Close"]] = function()
          self:close()
        end,
        ["<esc>"] = function()
          self:close()
        end,
        ["<c-k>"] = function()
          vim.cmd("normal! zc")

          vim.cmd("normal! k")
          while vim.fn.foldlevel(".") == 0 do
            vim.cmd("normal! k")
          end

          vim.cmd("normal! zo")
          vim.cmd("normal! zz")
        end,
        ["<c-j>"] = function()
          vim.cmd("normal! zc")

          vim.cmd("normal! j")
          while vim.fn.foldlevel(".") == 0 do
            vim.cmd("normal! j")
          end

          vim.cmd("normal! zo")
          vim.cmd("normal! zz")
        end,
        ["<tab>"] = function()
          pcall(vim.cmd, "normal! za")
        end,
      },
    },
    render = function()
      local win_width = vim.fn.winwidth(0)
      local function wrap_text(str)
        return text(util.remove_ansi_escape_codes(str))
      end

      return filter_map(self.state, function(item)
        local is_err = item.code ~= 0

        local code = string.format("%3d", item.code)
        local command = item.cmd
        for _, mask in ipairs(command_masks) do
          local stripped, count = command:gsub(mask, "")
          if count > 0 then
            command = stripped
            break
          end
        end
        local time = string.format("(%3.3f ms)", item.time)
        local stdio = string.format("[%s %3d]", "stdout", #item.stdout)

        local highlight_code = "NeojjCommandCodeNormal"

        if is_err then
          stdio = string.format("[%s %3d]", "stderr", #item.stderr)
          highlight_code = "NeojjCommandCodeError"
        end

        local spacing = string.rep(" ", win_width - #code - #command - #time - #stdio - 6)

        return col({
          row {
            text.highlight("NeojjGraphAuthor")(
              os.getenv("NEOJJ_DEBUG") and (item.hidden and "H" or " ") or ""
            ),
            text.highlight(highlight_code)(code),
            text(" "),
            text(command),
            text(spacing),
            text.highlight("NeojjCommandTime")(time),
            text(" "),
            text.highlight("NeojjCommandTime")(stdio),
          },
          col
            .padding_left("  | ")
            .highlight("NeojjCommandText")(map(util.merge(item.stdout, item.stderr), wrap_text)),
        }, { foldable = true, folded = true })
      end)
    end,
  }
end

return M
