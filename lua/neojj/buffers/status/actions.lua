-- NOTE: `v_` prefix stands for visual mode actions, `n_` for normal mode.
--
local a = require("plenary.async")
local jj = require("neojj.lib.jj")
local popups = require("neojj.popups")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local jump = require("neojj.lib.jump")

local fn = vim.fn

---@param self StatusBuffer
---@param item StatusItem
---@return integer[]|nil
local function translate_cursor_location(self, item)
  if rawget(item, "diff") then
    local line = self.buffer:cursor_line()

    for _, hunk in ipairs(item.diff.hunks) do
      if line >= hunk.first and line <= hunk.last then
        local offset = line - hunk.first
        local row = jump.adjust_row(hunk.disk_from, offset, hunk.lines, "-")
        return { row, 0 }
      end
    end
  end
end

local function open(type, path, cursor)
  jump.open(type, path, cursor, "[Status - Open]")
end

local M = {}

-- ============================================================
-- Visual mode actions
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.v_discard = function(self)
  return a.void(function()
    local selection = self.buffer.ui:get_selection()

    local file_count = 0
    local files_to_restore = {}

    for _, section in ipairs(selection.sections) do
      if section.name == "files" then
        file_count = file_count + #section.items
        for _, item in ipairs(section.items) do
          table.insert(files_to_restore, item.escaped_path)
        end
      end
    end

    if #files_to_restore > 0 then
      local message = ("Discard %s files?"):format(file_count)
      if input.get_permission(message) then
        jj.cli.restore.files(unpack(files_to_restore)).call()
        self:dispatch_refresh(nil, "v_discard")
      end
    end
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.v_diff_popup = function(self)
  return popups.open("diff", function(p)
    local section = self.buffer.ui:get_selection().section
    local item = self.buffer.ui:get_yankable_under_cursor()
    p { section = { name = section and section.name }, item = { name = item } }
  end)
end

---@param _self StatusBuffer
---@return fun(): nil
M.v_help_popup = function(_self)
  return popups.open("help")
end

---@param _self StatusBuffer
---@return fun(): nil
M.v_log_popup = function(_self)
  return popups.open("log")
end

-- ============================================================
-- Normal mode: Navigation
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_down = function(self)
  return function()
    if vim.v.count > 0 then
      vim.cmd("norm! " .. vim.v.count .. "j")
    else
      vim.cmd("norm! j")
    end

    if self.buffer:get_current_line()[1] == "" then
      vim.cmd("norm! j")
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_up = function(self)
  return function()
    if vim.v.count > 0 then
      vim.cmd("norm! " .. vim.v.count .. "k")
    else
      vim.cmd("norm! k")
    end

    if self.buffer:get_current_line()[1] == "" then
      vim.cmd("norm! k")
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_toggle = function(self)
  return function()
    local fold = self.buffer.ui:get_fold_under_cursor()
    if fold then
      if fold.options.on_open then
        fold.options.on_open(fold, self.buffer.ui)
      else
        local start, _ = fold:row_range_abs()
        local ok, _ = pcall(vim.cmd, "normal! za")
        if ok then
          self.buffer:move_cursor(start)
          fold.options.folded = not fold.options.folded
        end
      end
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_open_fold = function(self)
  return function()
    local fold = self.buffer.ui:get_fold_under_cursor()
    if fold then
      if fold.options.on_open then
        fold.options.on_open(fold, self.buffer.ui)
      else
        local start, _ = fold:row_range_abs()
        local ok, _ = pcall(vim.cmd, "normal! zo")
        if ok then
          self.buffer:move_cursor(start)
          fold.options.folded = false
        end
      end
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_close_fold = function(self)
  return function()
    local fold = self.buffer.ui:get_fold_under_cursor()
    if fold then
      local start, _ = fold:row_range_abs()
      local ok, _ = pcall(vim.cmd, "normal! zc")
      if ok then
        self.buffer:move_cursor(start)
        fold.options.folded = true
      end
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_close = function(self)
  return require("neojj.lib.ui.helpers").close_topmost(self)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_open_or_scroll_down = function(self)
  return function()
    local commit = self.buffer.ui:get_commit_under_cursor()
    if commit then
      require("neojj.buffers.commit_view").open_or_scroll_down(commit)
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_open_or_scroll_up = function(self)
  return function()
    local commit = self.buffer.ui:get_commit_under_cursor()
    if commit then
      require("neojj.buffers.commit_view").open_or_scroll_up(commit)
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_refresh_buffer = function(self)
  return a.void(function()
    self:dispatch_refresh({ update_diffs = { "*:*" } }, "n_refresh_buffer")
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_depth1 = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    if section then
      local start, last = section:row_range_abs()
      if self.buffer:cursor_line() < start or self.buffer:cursor_line() >= last then
        return
      end

      self.buffer:move_cursor(start)
      section:close_all_folds(self.buffer.ui)

      self.buffer.ui:update()
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_depth2 = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    local row = self.buffer.ui:get_component_under_cursor()

    if section then
      local start, last = section:row_range_abs()
      if self.buffer:cursor_line() < start or self.buffer:cursor_line() >= last then
        return
      end

      self.buffer:move_cursor(start)

      section:close_all_folds(self.buffer.ui)
      section:open_all_folds(self.buffer.ui, 1)

      self.buffer.ui:update()

      if row then
        local start, _ = row:row_range_abs()
        self.buffer:move_cursor(start)
      end
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_depth3 = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    local context = self.buffer.ui:get_cursor_context()

    if section then
      local start, last = section:row_range_abs()
      if self.buffer:cursor_line() < start or self.buffer:cursor_line() >= last then
        return
      end

      self.buffer:move_cursor(start)

      section:close_all_folds(self.buffer.ui)
      section:open_all_folds(self.buffer.ui, 2)
      section:close_all_folds(self.buffer.ui)
      section:open_all_folds(self.buffer.ui, 2)

      self.buffer.ui:update()

      if context then
        local start, _ = context:row_range_abs()
        self.buffer:move_cursor(start)
      end
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_depth4 = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    local context = self.buffer.ui:get_cursor_context()

    if section then
      local start, last = section:row_range_abs()
      if self.buffer:cursor_line() < start or self.buffer:cursor_line() >= last then
        return
      end

      self.buffer:move_cursor(start)
      section:close_all_folds(self.buffer.ui)
      section:open_all_folds(self.buffer.ui, 3)

      self.buffer.ui:update()

      if context then
        local start, _ = context:row_range_abs()
        self.buffer:move_cursor(start)
      end
    end
  end
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_command_history = function(_self)
  return a.void(function()
    require("neojj.buffers.git_command_history"):new():show()
  end)
end

-- ============================================================
-- Normal mode: Yank
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_yank_selected = function(self)
  return function()
    local yank = self.buffer.ui:get_yankable_under_cursor()
    if yank then
      yank = string.format("'%s'", yank)
      vim.cmd.let("@+=" .. yank)
      vim.cmd.echo(yank)
    else
      vim.cmd("echo ''")
    end
  end
end

-- ============================================================
-- Normal mode: Discard (jj restore)
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_discard = function(self)
  return a.void(function()
    local selection = self.buffer.ui:get_selection()
    if not selection.section then
      return
    end

    local section = selection.section.name
    local action, message

    if selection.item and selection.item.first == fn.line(".") then
      -- Discard a single file
      if section == "files" then
        message = ("Discard %q?"):format(selection.item.name)
        action = function()
          jj.cli.restore.files(selection.item.escaped_path).call()
        end
      end
    elseif selection.item then
      -- Discard hunk - for now, restore the whole file
      -- TODO: hunk-level restore when jj supports it
      if section == "files" then
        message = ("Discard changes in %q?"):format(selection.item.name)
        action = function()
          jj.cli.restore.files(selection.item.escaped_path).call()
        end
      end
    else
      -- Discard entire section
      if section == "files" then
        message = ("Discard all %s modified files?"):format(#selection.section.items)
        action = function()
          -- jj restore with no args restores all files
          jj.cli.restore.call()
        end
      end
    end

    if action and input.get_permission(message) then
      action()
      self:dispatch_refresh(nil, "n_discard")
    end
  end)
end

-- ============================================================
-- Normal mode: Hunk navigation
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_go_to_next_hunk_header = function(self)
  return function()
    local c = self.buffer.ui:get_component_under_cursor(function(c)
      return c.options.tag == "Diff" or c.options.tag == "Hunk" or c.options.tag == "Item"
    end)
    local section = self.buffer.ui:get_current_section()

    if c and section then
      local _, section_last = section:row_range_abs()
      local next_location

      if c.options.tag == "Diff" then
        next_location = fn.line(".") + 1
      elseif c.options.tag == "Item" then
        vim.cmd("normal! zo")
        next_location = fn.line(".") + 1
      elseif c.options.tag == "Hunk" then
        local _, last = c:row_range_abs()
        next_location = last + 1
      end

      if next_location < section_last then
        self.buffer:move_cursor(next_location)
      end

      vim.cmd("normal! zt")
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_go_to_previous_hunk_header = function(self)
  return function()
    local function previous_hunk_header(self, line)
      local c = self.buffer.ui:get_component_on_line(line, function(c)
        return c.options.tag == "Diff" or c.options.tag == "Hunk" or c.options.tag == "Item"
      end)

      if c then
        local first, _ = c:row_range_abs()
        if fn.line(".") == first then
          first = previous_hunk_header(self, line - 1)
        end

        return first
      end
    end

    local previous_header = previous_hunk_header(self, fn.line("."))
    if previous_header then
      self.buffer:move_cursor(previous_header)
      vim.cmd("normal! zt")
    end
  end
end

-- ============================================================
-- Normal mode: File open actions
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_goto_file = function(self)
  return function()
    local item = self.buffer.ui:get_item_under_cursor()

    -- Goto FILE
    if item and item.absolute_path then
      local cursor = translate_cursor_location(self, item)
      self:close()
      vim.schedule_wrap(open)("edit", item.absolute_path, cursor)
      return
    end

    -- Goto CHANGE (by change_id)
    local ref = self.buffer.ui:get_yankable_under_cursor()
    if ref then
      require("neojj.buffers.commit_view").new(ref):open()
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_tab_open = function(self)
  return function()
    local item = self.buffer.ui:get_item_under_cursor()

    if item and item.absolute_path then
      open("tabedit", item.absolute_path, translate_cursor_location(self, item))
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_split_open = function(self)
  return function()
    local item = self.buffer.ui:get_item_under_cursor()

    if item and item.absolute_path then
      open("split", item.absolute_path, translate_cursor_location(self, item))
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_vertical_split_open = function(self)
  return function()
    local item = self.buffer.ui:get_item_under_cursor()

    if item and item.absolute_path then
      open("vsplit", item.absolute_path, translate_cursor_location(self, item))
    end
  end
end

-- ============================================================
-- Normal mode: Section navigation
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_next_section = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    if section then
      local position = section.position.row_end + 2
      self.buffer:move_cursor(position)
    else
      self.buffer:move_cursor(self.buffer.ui:first_section().first + 1)
    end
  end
end

---@param self StatusBuffer
---@return fun(): nil
M.n_prev_section = function(self)
  return function()
    local section = self.buffer.ui:get_current_section()
    if section then
      local prev_section = self.buffer.ui:get_current_section(section.position.row_start - 1)
      if prev_section then
        self.buffer:move_cursor(prev_section.position.row_start + 1)
        return
      end
    end

    self.buffer:win_exec("norm! gg")
  end
end

-- ============================================================
-- Normal mode: jj-specific actions
-- ============================================================

---@param self StatusBuffer
---@return fun(): nil
M.n_describe = function(self)
  return a.void(function()
    local msg = input.get_user_input("Describe change")
    if not msg or msg == "" then
      return
    end

    jj.cli.describe.no_edit.message(msg).call()
    self:dispatch_refresh(nil, "n_describe")
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_new_change = function(self)
  return a.void(function()
    jj.cli.new.call()
    notification.info("Created new change")
    self:dispatch_refresh(nil, "n_new_change")
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_abandon = function(self)
  return a.void(function()
    if input.get_permission("Abandon current change?") then
      jj.cli.abandon.call()
      notification.info("Change abandoned")
      self:dispatch_refresh(nil, "n_abandon")
    end
  end)
end

-- ============================================================
-- Normal mode: Command
-- ============================================================

---@param self StatusBuffer|nil
---@return fun(): nil
M.n_command = function(self)
  local process = require("neojj.process")
  local runner = require("neojj.runner")

  return a.void(function()
    local cmd =
      input.get_user_input(("Run command in %s"):format(jj.repo.worktree_root), { prepend = "jj " })
    if not cmd then
      return
    end

    local cmd = vim.split(cmd, " ")
    table.insert(cmd, 2, "--no-pager")

    local proc = process.new {
      cmd = cmd,
      cwd = jj.repo.worktree_root,
      env = {},
      on_error = function()
        return false
      end,
      suppress_console = false,
      user_command = true,
    }

    proc:show_console()

    runner.call(proc, {
      pty = true,
      callback = function()
        if self then
          self:dispatch_refresh()
        end
      end,
    })
  end)
end

-- ============================================================
-- Popup actions
-- ============================================================

---@param _self StatusBuffer
---@return fun(): nil
M.n_bookmark_popup = function(_self)
  return popups.open("bookmark")
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_squash_popup = function(_self)
  return popups.open("squash")
end

---@param self StatusBuffer
---@return fun(): nil
M.n_diff_popup = function(self)
  return popups.open("diff", function(p)
    local section = self.buffer.ui:get_selection().section
    local item = self.buffer.ui:get_yankable_under_cursor()
    p {
      section = { name = section and section.name },
      item = { name = item },
    }
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_help_popup = function(self)
  return popups.open("help", function(p)
    local section = self.buffer.ui:get_selection().section
    local section_name
    if section then
      section_name = section.name
    end

    local item = self.buffer.ui:get_yankable_under_cursor()

    p {
      bookmark = {},
      change = {},
      commit = {},
      diff = {
        section = { name = section_name },
        item = { name = item },
      },
      remote = {},
      fetch = {},
      log = {},
      push = {},
      rebase = {},
      squash = {},
    }
  end)
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_remote_popup = function(_self)
  return popups.open("remote")
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_fetch_popup = function(_self)
  return popups.open("fetch")
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_log_popup = function(_self)
  return popups.open("log")
end

---@param self StatusBuffer
---@return fun(): nil
M.n_push_popup = function(self)
  return popups.open("push", function(p)
    p {}
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_rebase_popup = function(self)
  return popups.open("rebase", function(p)
    p {}
  end)
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_commit_popup = function(_self)
  return popups.open("commit")
end

---@param self StatusBuffer
---@return fun(): nil
M.n_open_in_browser = function(self)
  return function()
    local change_id = self.buffer.ui:get_yankable_under_cursor()
    if not change_id then
      notification.warn("No change under cursor", { dismiss = true })
      return
    end

    -- Get the git commit hash for this change
    local result = jj.cli.log.no_graph.template('"" ++ commit_id ++ ""').revisions(change_id).limit(1).call { hidden = true, trim = true }
    if not result or result.code ~= 0 or not result.stdout[1] then
      notification.warn("Could not resolve commit", { dismiss = true })
      return
    end
    local commit_hash = result.stdout[1]

    -- Get remote URL
    local shell = require("neojj.lib.jj.shell")
    local remote_lines, code = shell.exec(
      { "jj", "--no-pager", "--color=never", "git", "remote", "list" },
      jj.repo.state.worktree_root
    )
    if code ~= 0 or not remote_lines or #remote_lines == 0 then
      notification.warn("No remote found", { dismiss = true })
      return
    end

    -- Parse first remote URL (format: "origin https://github.com/user/repo.git")
    local remote_url
    for _, line in ipairs(remote_lines) do
      local url = line:match("^%S+%s+(%S+)")
      if url then
        remote_url = url
        break
      end
    end

    if not remote_url then
      notification.warn("Could not parse remote URL", { dismiss = true })
      return
    end

    -- Convert git URL to browser URL
    local browser_url = remote_url
      :gsub("%.git$", "")
      :gsub("^git@([^:]+):", "https://%1/")
      :gsub("^ssh://git@([^/]+)/", "https://%1/")

    -- Construct commit URL (works for GitHub, GitLab, etc.)
    browser_url = browser_url .. "/commit/" .. commit_hash

    vim.ui.open(browser_url)
  end
end

return M
