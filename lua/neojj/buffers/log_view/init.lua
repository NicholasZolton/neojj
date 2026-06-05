local Buffer = require("neojj.lib.buffer")
local ui = require("neojj.buffers.log_view.ui")
local common = require("neojj.buffers.common")
local config = require("neojj.config")
local popups = require("neojj.popups")
local status_maps = require("neojj.config").get_reversed_status_maps()
local CommitViewBuffer = require("neojj.buffers.commit_view")
local util = require("neojj.lib.util")
local a = require("plenary.async")

---@class LogViewBuffer
---@field commits NeojjChangeLogEntry[]
---@field remotes string[]
---@field internal_args table
---@field files string[]
---@field buffer Buffer
---@field header string
---@field fetch_func fun(offset: number): NeojjChangeLogEntry[]
---@field refresh_lock Semaphore
local M = {}
M.__index = M

---Opens a popup for selecting a commit
---@param commits NeojjChangeLogEntry[]|nil
---@param internal_args table|nil
---@param files string[]|nil list of files to filter by
---@param fetch_func fun(offset: number): NeojjChangeLogEntry[]
---@param header string
---@param remotes string[]
---@return LogViewBuffer
function M.new(commits, internal_args, files, fetch_func, header, remotes)
  local instance = {
    files = files,
    commits = commits,
    remotes = remotes,
    internal_args = internal_args,
    fetch_func = fetch_func,
    buffer = nil,
    refresh_lock = a.control.Semaphore.new(1),
    header = header,
  }

  setmetatable(instance, M)

  return instance
end

function M:commit_count()
  return #util.filter_map(self.commits, function(commit)
    if commit.change_id then
      return 1
    end
  end)
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

function M:open()
  if M.is_open() then
    M.instance.buffer:focus()
    return
  end

  M.instance = self

  local function guarded(action)
    return function()
      if common.divergent_guard(self.buffer.ui:get_commit_item_under_cursor()) then
        return
      end
      action()
    end
  end

  self.buffer = Buffer.create {
    name = "NeojjLogView",
    filetype = "NeojjLogView",
    kind = config.values.log_view.kind,
    context_highlight = false,
    header = self.header,
    scroll_header = false,
    active_item_highlight = true,
    status_column = not config.values.disable_signs and "" or nil,
    mappings = {
      v = {
        [popups.mapping_for("CommitPopup")] = guarded(popups.open("commit", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("FetchPopup")] = popups.open("fetch"),
        [popups.mapping_for("PushPopup")] = guarded(popups.open("push", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("RebasePopup")] = guarded(popups.open("rebase", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("RemotePopup")] = popups.open("remote"),
        [popups.mapping_for("DiffPopup")] = popups.open("diff", function(p)
          local items = self.buffer.ui:get_ordered_commits_in_selection()
          p {
            section = { name = "log" },
            item = { name = items },
          }
        end),
        [popups.mapping_for("BookmarkPopup")] = guarded(popups.open("bookmark", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("SquashPopup")] = guarded(popups.open("squash", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
      },
      n = {
        [popups.mapping_for("CommitPopup")] = guarded(popups.open("commit", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("FetchPopup")] = popups.open("fetch"),
        [popups.mapping_for("PushPopup")] = guarded(popups.open("push", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("RebasePopup")] = guarded(popups.open("rebase", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("RemotePopup")] = popups.open("remote"),
        [popups.mapping_for("DiffPopup")] = guarded(popups.open("diff", function(p)
          local commit = self.buffer.ui:get_commit_under_cursor()
          p {
            section = { name = "log" },
            item = { name = commit },
          }
        end)),
        [popups.mapping_for("LogPopup")] = popups.open("log"),
        [popups.mapping_for("BookmarkPopup")] = guarded(popups.open("bookmark", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [popups.mapping_for("SquashPopup")] = guarded(popups.open("squash", function(p)
          p { commit = self.buffer.ui:get_commit_under_cursor() }
        end)),
        [status_maps["YankSelected"]] = function()
          local yank = self.buffer.ui:get_commit_under_cursor()
          if yank then
            yank = string.format("'%s'", yank)
            vim.cmd.let("@+=" .. yank)
            vim.cmd.echo(yank)
          else
            vim.cmd("echo ''")
          end
        end,
        ["dd"] = function()
          local item = self.buffer.ui:get_commit_item_under_cursor()
          if not (item and item.change_offset ~= nil) then
            return
          end
          CommitViewBuffer.new(item.commit_id, self.files):open()
        end,
        ["x"] = function()
          local item = self.buffer.ui:get_commit_item_under_cursor()
          common.abandon_at_cursor(item, function()
            a.run(function()
              local permit = self.refresh_lock:acquire()
              self.commits = self.fetch_func(0)
              self.buffer.ui:render(unpack(ui.View(self.commits, self.remotes, self.internal_args)))
              permit:forget()
            end)
          end)
        end,
        ["<esc>"] = require("neojj.lib.ui.helpers").close_topmost(self),
        [status_maps["Close"]] = require("neojj.lib.ui.helpers").close_topmost(self),
        [status_maps["GoToFile"]] = guarded(function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.new(commit, self.files):open()
          end
        end),
        [status_maps["PeekFile"]] = guarded(function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            local buffer = CommitViewBuffer.new(commit, self.files):open()
            buffer.buffer:win_call(vim.cmd, "normal! gg")

            self.buffer:focus()
          end
        end),
        [status_maps["OpenOrScrollDown"]] = guarded(function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.open_or_scroll_down(commit, self.files)
          end
        end),
        [status_maps["OpenOrScrollUp"]] = guarded(function()
          local commit = self.buffer.ui:get_commit_under_cursor()
          if commit then
            CommitViewBuffer.open_or_scroll_up(commit, self.files)
          end
        end),
        [status_maps["PeekUp"]] = function()
          -- Open prev fold
          pcall(vim.cmd, "normal! zc")

          vim.cmd("normal! k")
          for _ = vim.fn.line("."), 0, -1 do
            if vim.fn.foldlevel(".") > 0 then
              break
            end

            vim.cmd("normal! k")
          end

          if CommitViewBuffer.is_open() then
            local item = self.buffer.ui:get_commit_item_under_cursor()
            -- Skip update on divergent parent lines (no single commit to show)
            if item and not item.variants then
              local commit = self.buffer.ui:get_commit_under_cursor()
              if commit then
                CommitViewBuffer.instance:update(commit, self.files)
              end
            end
          else
            pcall(vim.cmd, "normal! zo")
            vim.cmd("normal! zz")
          end
        end,
        [status_maps["PeekDown"]] = function()
          pcall(vim.cmd, "normal! zc")

          vim.cmd("normal! j")
          for _ = vim.fn.line("."), vim.fn.line("$"), 1 do
            if vim.fn.foldlevel(".") > 0 then
              break
            end

            vim.cmd("normal! j")
          end

          if CommitViewBuffer.is_open() then
            local item = self.buffer.ui:get_commit_item_under_cursor()
            -- Skip update on divergent parent lines (no single commit to show)
            if item and not item.variants then
              local commit = self.buffer.ui:get_commit_under_cursor()
              if commit then
                CommitViewBuffer.instance:update(commit, self.files)
              end
            end
          else
            pcall(vim.cmd, "normal! zo")
            vim.cmd("normal! zz")
          end
        end,
        ["+"] = a.void(function()
          local permit = self.refresh_lock:acquire()

          self.commits = util.merge(self.commits, self.fetch_func(self:commit_count()))
          self.buffer.ui:render(unpack(ui.View(self.commits, self.remotes, self.internal_args)))

          permit:forget()
        end),
        ["<tab>"] = function()
          pcall(vim.cmd, "normal! za")
        end,
        ["j"] = function()
          if vim.v.count > 0 then
            vim.cmd("norm! " .. vim.v.count .. "j")
          else
            vim.cmd("norm! j")
          end

          while true do
            local line = self.buffer:get_current_line()[1]
            -- Stop on: the original commit lines (start with non-space) AND on variant rows
            -- (start with spaces but contain a '/' followed by a digit after the indent).
            local is_landable = line:sub(1, 1) ~= " " or line:match("^%s+/%d")
            if is_landable then
              break
            end
            if vim.fn.line(".") == vim.fn.line("$") then
              break
            end
            vim.cmd("norm! j")
          end
        end,
        ["k"] = function()
          if vim.v.count > 0 then
            vim.cmd("norm! " .. vim.v.count .. "k")
          else
            vim.cmd("norm! k")
          end

          while true do
            local line = self.buffer:get_current_line()[1]
            local is_landable = line:sub(1, 1) ~= " " or line:match("^%s+/%d")
            if is_landable then
              break
            end
            if vim.fn.line(".") == 1 then
              break
            end
            vim.cmd("norm! k")
          end
        end,
      },
    },
    render = function()
      return ui.View(self.commits, self.remotes, self.internal_args)
    end,
    after = function(buffer)
      -- First line is empty, so move cursor to second line.
      buffer:move_cursor(2)
    end,
  }
end

return M
