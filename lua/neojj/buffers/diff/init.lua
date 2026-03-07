local Buffer = require("neojj.lib.buffer")
local ui = require("neojj.buffers.diff.ui")
local jj = require("neojj.lib.jj")
local config = require("neojj.config")

local api = vim.api

---@class DiffBuffer
---@field buffer Buffer
---@field open fun(self): DiffBuffer
---@field close fun()
---@field stats table
---@field diffs table
---@field header string
---@see Buffer
---@see Ui
local M = {}
M.__index = M

---@param header string
---@return DiffBuffer
function M:new(header)
  -- Get diff stat using --ignore-working-copy since jj describe may hold the lock
  local shell = require("neojj.lib.jj.shell")
  local cwd
  local ok, repo = pcall(function() return jj.repo end)
  if ok and repo then
    cwd = repo.worktree_root
  end
  cwd = cwd or vim.fn.getcwd()

  local stat_lines_raw, stat_code = shell.exec({
    "jj", "--no-pager", "--color=never", "--ignore-working-copy",
    "-R", cwd,
    "diff", "--stat",
  }, cwd)

  local stat_lines = (stat_code == 0 and stat_lines_raw) or {}
  local stats = {
    summary = "",
    files = {},
  }
  if #stat_lines > 0 then
    stats.summary = stat_lines[#stat_lines] or ""
    for i = 1, #stat_lines - 1 do
      local file = {}
      if stat_lines[i] ~= "" then
        file.path, file.changes, file.insertions, file.deletions =
          stat_lines[i]:match("^%s*(.-)%s+|%s+(%d+) ?(%+*)(%-*)")
        if not file.path then
          file.path, file.changes = stat_lines[i]:match("^%s*(.-)%s+|%s+(Bin .*)$")
        end
        if file.path then
          table.insert(stats.files, file)
        end
      end
    end
  end

  -- Get full diff for the working copy using --ignore-working-copy
  local diffs = {}
  local diff_lines_raw, diff_code = shell.exec({
    "jj", "--no-pager", "--color=never", "--ignore-working-copy",
    "-R", cwd,
    "diff", "--git",
  }, cwd)

  if diff_code == 0 and diff_lines_raw and #diff_lines_raw > 0 then
    -- Split the combined diff output into per-file diffs
    local current_file_lines = {}
    for _, line in ipairs(diff_lines_raw) do
      if line:match("^diff %-%-git ") and #current_file_lines > 0 then
        table.insert(diffs, jj.diff.parse(current_file_lines))
        current_file_lines = {}
      end
      table.insert(current_file_lines, line)
    end
    if #current_file_lines > 0 then
      table.insert(diffs, jj.diff.parse(current_file_lines))
    end
  end

  local instance = {
    buffer = nil,
    header = header,
    stats = stats,
    diffs = diffs,
  }

  setmetatable(instance, self)
  return instance
end

--- Closes the DiffBuffer
function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end
end

---Opens the DiffBuffer
---If already open will close the buffer
---@return DiffBuffer
function M:open()
  if vim.tbl_isempty(self.stats.files) then
    return self
  end

  local status_maps = config.get_reversed_status_maps()

  self.buffer = Buffer.create {
    name = "NeoJJDiffView",
    filetype = "NeoJJDiffView",
    status_column = not config.values.disable_signs and "" or nil,
    kind = config.values.commit_editor.staged_diff_split_kind,
    context_highlight = not config.values.disable_context_highlighting,
    mappings = {
      n = {
        ["{"] = function() -- Goto Previous
          local function previous_hunk_header(self, line)
            local c = self.buffer.ui:get_component_on_line(line, function(c)
              return c.options.tag == "Diff" or c.options.tag == "Hunk"
            end)

            if c then
              local first, _ = c:row_range_abs()
              if vim.fn.line(".") == first then
                first = previous_hunk_header(self, line - 1)
              end

              return first
            end
          end

          local previous_header = previous_hunk_header(self, vim.fn.line("."))
          if previous_header then
            api.nvim_win_set_cursor(0, { previous_header, 0 })
            vim.cmd("normal! zt")
          end
        end,
        ["}"] = function() -- Goto next
          local c = self.buffer.ui:get_component_under_cursor(function(c)
            return c.options.tag == "Diff" or c.options.tag == "Hunk"
          end)

          if c then
            if c.options.tag == "Diff" then
              self.buffer:move_cursor(vim.fn.line(".") + 1)
            else
              local _, last = c:row_range_abs()
              if last == vim.fn.line("$") then
                self.buffer:move_cursor(last)
              else
                self.buffer:move_cursor(last + 1)
              end
            end
            vim.cmd("normal! zt")
          end
        end,
        [status_maps["Toggle"]] = function()
          pcall(vim.cmd, "normal! za")
        end,
        [status_maps["Close"]] = function()
          self:close()
        end,
      },
    },
    render = function()
      return ui.DiffView(self.header, self.stats, self.diffs)
    end,
    after = function()
      vim.cmd("normal! zR")
      vim.wo.colorcolumn = ""
    end,
  }

  return self
end

return M
