local Buffer = require("neojj.lib.buffer")
local parser = require("neojj.buffers.commit_view.parsing")
local ui = require("neojj.buffers.commit_view.ui")
local jj = require("neojj.lib.jj")
local config = require("neojj.config")
local popups = require("neojj.popups")
local commit_view_maps = require("neojj.config").get_reversed_commit_view_maps()
local status_maps = require("neojj.config").get_reversed_status_maps()
local notification = require("neojj.lib.notification")
local jump = require("neojj.lib.jump")
local util = require("neojj.lib.util")

local api = vim.api

---@class CommitInfo
---@field oid string Change ID (primary identifier)
---@field change_id string Change ID
---@field commit_id string Commit ID
---@field commit_arg string The change argument passed to `jj show`
---@field author_email string
---@field author_name string
---@field author_date string
---@field description table
---@field diffs table
---@field bookmarks string[]
---@field empty boolean
---@field conflict boolean

---@class CommitOverview
---@field summary string a short summary about what happened
---@field files CommitOverviewFile[] a list of CommitOverviewFile

---@class CommitOverviewFile
---@field path string the path to the file relative to the workspace root
---@field changes string how many changes were made to the file
---@field insertions string insertion count visualized as list of `+`
---@field deletions string deletion count visualized as list of `-`

--- @class CommitViewBuffer
--- @field commit_info CommitInfo
--- @field commit_overview CommitOverview
--- @field buffer Buffer
--- @field open fun(self, kind?: string)
--- @field close fun()
--- @see CommitInfo
--- @see Buffer
--- @see Ui
local M = {
  instance = nil,
}

---Build commit_info from jj show output
---@param change_id string
---@return CommitInfo
local function build_commit_info(change_id)
  -- Get change metadata via template
  local tpl = 'change_id.short(12) ++ "\\n" ++ commit_id.short(12) ++ "\\n" ++ author.name() ++ "\\n" ++ author.email() ++ "\\n" ++ author.timestamp() ++ "\\n" ++ description'
  local meta_result = jj.cli.show.template(tpl).args(change_id).call { hidden = true, trim = false }

  local info = {
    oid = change_id,
    change_id = "",
    commit_id = "",
    commit_arg = change_id,
    author_name = "",
    author_email = "",
    author_date = "",
    description = {},
    diffs = {},
    bookmarks = {},
    empty = false,
    conflict = false,
  }

  if meta_result and meta_result.code == 0 and #meta_result.stdout > 0 then
    local lines = meta_result.stdout
    info.change_id = (lines[1] or ""):gsub("%s+$", "")
    info.commit_id = (lines[2] or ""):gsub("%s+$", "")
    info.author_name = (lines[3] or ""):gsub("%s+$", "")
    info.author_email = (lines[4] or ""):gsub("%s+$", "")
    info.author_date = (lines[5] or ""):gsub("%s+$", "")
    -- Remaining lines are the description
    local desc = {}
    for i = 6, #lines do
      table.insert(desc, lines[i])
    end
    -- Remove trailing empty lines
    while #desc > 0 and desc[#desc] == "" do
      table.remove(desc)
    end
    if #desc == 0 then
      desc = { "(no description)" }
    end
    info.description = desc
    info.oid = info.change_id
  end

  -- Get diff in git format
  local diff_result = jj.cli.show.git.args(change_id).call { hidden = true, trim = true }
  if diff_result and diff_result.code == 0 and #diff_result.stdout > 0 then
    -- Split the diff output into per-file diffs
    local raw_lines = diff_result.stdout
    local diffs = {}
    local current_diff_lines = {}

    for _, line in ipairs(raw_lines) do
      if line:match("^diff %-%-git") then
        if #current_diff_lines > 0 then
          table.insert(diffs, jj.diff.parse(current_diff_lines))
          current_diff_lines = {}
        end
      end
      table.insert(current_diff_lines, line)
    end
    if #current_diff_lines > 0 then
      table.insert(diffs, jj.diff.parse(current_diff_lines))
    end

    info.diffs = diffs
  end

  return info
end

---Creates a new CommitViewBuffer
---@param change_id string the change ID
---@param filter? string[] Filter diffs to filepaths in table
---@return CommitViewBuffer
function M.new(change_id, filter)
  local commit_info = build_commit_info(change_id)

  local commit_overview =
    parser.parse_commit_overview(jj.cli.show.stat.args(change_id).call({ hidden = true }).stdout or {})

  local instance = {
    item_filter = filter,
    commit_info = commit_info,
    commit_overview = commit_overview,
    buffer = nil,
  }

  setmetatable(instance, { __index = M })

  return instance
end

--- Closes the CommitViewBuffer
function M:close()
  if self.buffer then
    self.buffer:close()
    self.buffer = nil
  end

  M.instance = nil
end

---@return string
function M.current_oid()
  if M.is_open() then
    return M.instance.commit_info.oid
  else
    return "null-oid"
  end
end

---Opens the CommitViewBuffer if it isn't open or performs the given action
---which is passed the window id of the commit view buffer
---@param change_id string change
---@param filter string[]? Filter diffs to filepaths in table
---@param cmd string vim command to run in window
function M.open_or_run_in_window(change_id, filter, cmd)
  assert(change_id, "change id cannot be nil")

  if M.is_open() and M.instance.commit_info.commit_arg == change_id then
    M.instance.buffer:win_exec(cmd)
  else
    M:close()
    local cw = api.nvim_get_current_win()
    M.new(change_id, filter):open()
    api.nvim_set_current_win(cw)
  end
end

---@param change_id string change
---@param filter string[]? Filter diffs to filepaths in table
function M.open_or_scroll_down(change_id, filter)
  M.open_or_run_in_window(change_id, filter, "normal! " .. vim.keycode("<c-d>"))
end

---@param change_id string change
---@param filter string[]? Filter diffs to filepaths in table
function M.open_or_scroll_up(change_id, filter)
  M.open_or_run_in_window(change_id, filter, "normal! " .. vim.keycode("<c-u>"))
end

---@return boolean
function M.is_open()
  return (M.instance and M.instance.buffer and M.instance.buffer:is_visible()) == true
end

---Updates an already open buffer to show a new commit
---@param change_id string change
---@param filter string[]? Filter diffs to filepaths in table
function M:update(change_id, filter)
  assert(change_id, "change id cannot be nil")

  local commit_info = build_commit_info(change_id)
  local commit_overview =
    parser.parse_commit_overview(jj.cli.show.stat.args(change_id).call({ hidden = true }).stdout or {})

  self.item_filter = filter
  self.commit_info = commit_info
  self.commit_overview = commit_overview

  self.buffer.ui:render(
    unpack(ui.CommitView(self.commit_info, self.commit_overview, self.item_filter))
  )

  self.buffer:win_call(vim.cmd, "normal! gg")
end

---Generate a callback to re-open CommitViewBuffer in the current commit
---@param self CommitViewBuffer
---@return fun()
local function get_reopen_cb(self)
  local original_cursor = api.nvim_win_get_cursor(0)
  local back_change = self.commit_info.oid
  return function()
    M.new(back_change):open()
    api.nvim_win_set_cursor(0, original_cursor)
  end
end

---@param self CommitViewBuffer
---@param location LocationInHunk
---@return string|nil, integer[]
local function location_to_commit_cursor(self, location)
  if string.sub(location.line, 1, 1) == "-" then
    -- For the "old" side, use the parent revision
    -- jj doesn't have git.log.parent() — use change_id- as parent
    return self.commit_info.change_id .. "-", { location.old, 0 }
  else
    return self.commit_info.change_id, { location.new, 0 }
  end
end

---Visit the file at the location specified by the provided hunk component
---@param self CommitViewBuffer
---@param component Component A component that evaluates is_jumpable_hunk_line_component() to true
---@param worktree boolean if true, try to jump to the file in the current worktree. Otherwise jump to the file in the referenced commit
local function diff_visit_file(self, component, worktree)
  local hunk_component = component.parent.parent
  local hunk = hunk_component.options.hunk
  local path = vim.trim(hunk.file)
  if path == "" then
    notification.warn("Unable to determine file path for diff line")
    return
  end

  local line = self.buffer:cursor_line()
  local offset = line - hunk_component.position.row_start
  local location = jump.translate_hunk_location(hunk, offset)
  if not location then
    return
  end

  if worktree then
    local cursor = { location.new, 0 }
    jump.goto_file_at(path, cursor)
  else
    local target_commit, cursor = location_to_commit_cursor(self, location)
    if not target_commit then
      notification.warn("Unable to retrieve parent change")
      return nil, cursor
    end
    jump.goto_file_in_commit_at(target_commit, path, cursor, get_reopen_cb(self))
  end
end

---@param c Component
---@return boolean
local function is_jumpable_hunk_line_component(c)
  return c.options.line_hl == "NeoJJDiffContext"
    or c.options.line_hl == "NeoJJDiffAdd"
    or c.options.line_hl == "NeoJJDiffDelete"
end

---Opens the CommitViewBuffer
---If already open will close the buffer
---@param kind? string
---@return CommitViewBuffer
function M:open(kind)
  kind = kind or config.values.commit_view.kind

  M.instance = self

  self.buffer = Buffer.create {
    name = "NeoJJCommitView",
    filetype = "NeoJJCommitView",
    kind = kind,
    status_column = not config.values.disable_signs and "" or nil,
    context_highlight = not config.values.disable_context_highlighting,
    autocmds = {
      ["WinLeave"] = function()
        if self.buffer and self.buffer.kind == "floating" then
          self:close()
        end
      end,
    },
    mappings = {
      n = {
        [commit_view_maps["OpenFileInWorktree"]] = function()
          local c = self.buffer.ui:get_component_under_cursor(function(c)
            return is_jumpable_hunk_line_component(c)
          end)
          if c then
            diff_visit_file(self, c, true)
          end
        end,
        ["<cr>"] = function()
          local c = self.buffer.ui:get_component_under_cursor(function(c)
            return c.options.highlight == "NeoJJFilePath" or is_jumpable_hunk_line_component(c)
          end)

          if not c then
            return
          end

          if is_jumpable_hunk_line_component(c) then
            diff_visit_file(self, c, false)
            return
          end

          -- Some paths are padded for formatting purposes. We need to trim them
          -- in order to use them as match patterns.
          local selected_path = vim.fn.trim(c.value)

          -- Recursively navigate the layout until we hit NeoJJDiffHeader leaf nodes
          local diff_headers = {}
          local function find_diff_headers(layout)
            if layout.children then
              for _, val in pairs(layout.children) do
                local v = find_diff_headers(val)
                if v then
                  diff_headers[vim.fn.trim(v[1])] = v[2]
                end
              end
            else
              if layout.options.line_hl == "NeoJJDiffHeader" then
                return { layout.value, layout:row_range_abs() }
              end
            end
          end

          find_diff_headers(self.buffer.ui.layout)

          -- Search for a match and jump if we find it
          for path, line_nr in pairs(diff_headers) do
            local path_norm = path
            for _, file_kind in ipairs { "modified", "renamed", "new file", "deleted file" } do
              if vim.startswith(path_norm, file_kind .. " ") then
                path_norm = string.sub(path_norm, string.len(file_kind) + 2)
                break
              end
            end
            path_norm = path_norm:gsub(" %-> ", " => ")

            if path_norm == selected_path then
              vim.cmd("normal! m'")
              self.buffer:move_cursor(line_nr)
              break
            end
          end
        end,
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
        [popups.mapping_for("CommitPopup")] = popups.open("commit", function(p)
          p { commit = self.commit_info.oid }
        end),
        [popups.mapping_for("DiffPopup")] = popups.open("diff", function(p)
          p {
            section = { name = "log" },
            item = { name = self.commit_info.oid },
          }
        end),
        [popups.mapping_for("FetchPopup")] = popups.open("fetch"),
        [popups.mapping_for("LogPopup")] = popups.open("log"),
        [popups.mapping_for("PushPopup")] = popups.open("push", function(p)
          p { commit = self.commit_info.oid }
        end),
        [popups.mapping_for("RebasePopup")] = popups.open("rebase", function(p)
          p { commit = self.commit_info.oid }
        end),
        [popups.mapping_for("RemotePopup")] = popups.open("remote"),
        [popups.mapping_for("BookmarkPopup")] = popups.open("bookmark", function(p)
          p { commit = self.commit_info.oid }
        end),
        [popups.mapping_for("SquashPopup")] = popups.open("squash", function(p)
          p { commit = self.commit_info.oid }
        end),
        [status_maps["Close"]] = function()
          self:close()
        end,
        ["<esc>"] = function()
          self:close()
        end,
        [status_maps["YankSelected"]] = popups.open("yank", function(p)
          -- If the cursor is over a specific hunk, just copy that diff.
          local diff
          local c = self.buffer.ui:get_component_under_cursor(function(c)
            return c.options.hunk ~= nil
          end)

          if c then
            local hunks = util.flat_map(self.commit_info.diffs, function(d)
              return d.hunks
            end)

            for _, hunk in ipairs(hunks) do
              if hunk.hash == c.options.hunk.hash then
                diff = table.concat(util.merge({ hunk.line }, hunk.lines), "\n")
                break
              end
            end
          end

          -- Fall back to entire patch
          if not diff then
            diff = table.concat(
              vim.tbl_map(function(d)
                return table.concat(d.lines, "\n")
              end, self.commit_info.diffs),
              "\n"
            )
          end

          p {
            hash = self.commit_info.oid,
            subject = self.commit_info.description[1],
            message = table.concat(self.commit_info.description, "\n"),
            body = table.concat(
              util.slice(self.commit_info.description, 2, #self.commit_info.description),
              "\n"
            ),
            diff = diff,
            author = ("%s <%s>"):format(self.commit_info.author_name, self.commit_info.author_email),
          }
        end),
        [status_maps["Toggle"]] = function()
          pcall(vim.cmd, "normal! za")
        end,
      },
    },
    render = function()
      return ui.CommitView(self.commit_info, self.commit_overview, self.item_filter)
    end,
    after = function()
      vim.cmd("normal! zR")
    end,
  }

  return self
end

return M
