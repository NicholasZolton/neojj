-- NOTE: `v_` prefix stands for visual mode actions, `n_` for normal mode.
--
local a = require("plenary.async")
local jj = require("neojj.lib.jj")
local popups = require("neojj.popups")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local jump = require("neojj.lib.jump")

local fn = vim.fn

---@class CursorContext
---@field change_id string|nil The change ID under cursor (from item, yankable, or head fallback)
---@field section string|nil Section name (e.g. "files", "recent", "bookmarks")
---@field item table|nil The item under cursor (from get_selection)
---@field yank string|nil Raw yankable value under cursor
---@field immutable boolean Whether the change is immutable

--- Resolve cursor context into a structured result.
--- Extracts change_id from item > yankable (head/parent) > nil.
---@param self StatusBuffer
---@return CursorContext
local function cursor_context(self)
  local selection = self.buffer.ui:get_selection()
  local item = selection.item
  local section = selection.section and selection.section.name
  local yank = self.buffer.ui:get_yankable_under_cursor()

  local change_id
  if item and item.change_id then
    change_id = item.change_id
  elseif yank and (yank == jj.repo.state.head.change_id or yank == jj.repo.state.parent.change_id) then
    change_id = yank
  end

  return {
    change_id = change_id,
    section = section,
    item = item,
    yank = yank,
    immutable = (item and item.immutable) or false,
  }
end

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
          table.insert(files_to_restore, item.fileset_path)
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
    local ref = self.buffer.ui:get_commit_under_cursor()
      or self.buffer.ui:get_yankable_under_cursor()
    p { section = { name = section and section.name }, item = { name = ref } }
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
    local ctx = cursor_context(self)
    if ctx.change_id then
      local short = ctx.change_id:sub(1, 8)
      vim.fn.setreg("+", short)
      vim.cmd.echo(string.format("'%s'", short))
    elseif ctx.yank then
      vim.fn.setreg("+", ctx.yank)
      vim.cmd.echo(string.format("'%s'", ctx.yank))
    else
      vim.cmd("echo ''")
    end
  end
end

M.n_yank_commit_hash = function(self)
  return function()
    local ctx = cursor_context(self)
    if ctx.item and ctx.item.commit_id then
      local short = ctx.item.commit_id:sub(1, 8)
      vim.fn.setreg("+", short)
      vim.cmd.echo(string.format("'%s'", short))
    elseif ctx.yank then
      vim.fn.setreg("+", ctx.yank)
      vim.cmd.echo(string.format("'%s'", ctx.yank))
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
          jj.cli.restore.files(selection.item.fileset_path).call()
        end
      end
    elseif selection.item then
      -- Discard hunk - for now, restore the whole file
      -- TODO: hunk-level restore when jj supports it
      if section == "files" then
        message = ("Discard changes in %q?"):format(selection.item.name)
        action = function()
          jj.cli.restore.files(selection.item.fileset_path).call()
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

---@param self StatusBuffer
---@return fun(): nil
M.n_context_delete = function(self)
  return a.void(function()
    local ctx = cursor_context(self)
    if not ctx.section then
      return
    end

    local item = ctx.item

    if ctx.section == "files" then
      -- Delegate to discard logic for files
      local action, message
      if item and item.first == fn.line(".") then
        message = ("Discard %q?"):format(item.name)
        action = function()
          jj.cli.restore.files(item.fileset_path).call()
        end
      elseif item then
        message = ("Discard changes in %q?"):format(item.name)
        action = function()
          jj.cli.restore.files(item.fileset_path).call()
        end
      else
        message = "Discard all modified files?"
        action = function()
          jj.cli.restore.call()
        end
      end
      if action and input.get_permission(message) then
        action()
        self:dispatch_refresh(nil, "n_context_delete")
      end
    elseif ctx.section == "recent" and item and item.change_id then
      local short = item.change_id:sub(1, 8)
      if item.immutable then
        notification.warn("Cannot abandon immutable commit " .. short, { dismiss = true })
        return
      end
      if not input.get_permission("Abandon " .. short .. "?") then
        return
      end
      local result = jj.cli.abandon.args(item.change_id).call()
      if result and result.code == 0 then
        local picker_cache = require("neojj.lib.picker_cache")
        picker_cache.remove_revision(item.change_id)
        notification.info("Abandoned " .. short, { dismiss = true })
        self:dispatch_refresh(nil, "n_context_delete")
      else
        notification.warn("Failed to abandon " .. short, { dismiss = true })
      end
    elseif ctx.section == "bookmarks" and item and item.name then
      if item.remote and item.remote ~= "" then
        notification.warn("Cannot delete remote bookmark " .. item.name .. "@" .. item.remote .. " — delete locally and push to remove", { dismiss = true })
        return
      end
      if item.deleted then
        if not input.get_permission("Restore bookmark " .. item.name .. "?") then
          return
        end
        local result = jj.cli.bookmark_set.args(item.name, "-r", item.name .. "@origin").call()
        if result and result.code == 0 then
          local picker_cache = require("neojj.lib.picker_cache")
          picker_cache.invalidate_bookmarks()
          notification.info("Restored bookmark " .. item.name, { dismiss = true })
          self:dispatch_refresh(nil, "n_context_delete")
        else
          notification.warn("Failed to restore bookmark " .. item.name, { dismiss = true })
        end
        return
      end
      if not input.get_permission("Delete bookmark " .. item.name .. "?") then
        return
      end
      local result = jj.cli.bookmark_delete.args(item.name).call()
      if result and result.code == 0 then
        local picker_cache = require("neojj.lib.picker_cache")
        picker_cache.invalidate_bookmarks()
        notification.info("Deleted bookmark " .. item.name, { dismiss = true })
        self:dispatch_refresh(nil, "n_context_delete")
      else
        notification.warn("Failed to delete bookmark " .. item.name, { dismiss = true })
      end
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

    -- Goto CHANGE (by change_id from oid, then yankable as fallback)
    local ref = self.buffer.ui:get_commit_under_cursor()
      or self.buffer.ui:get_yankable_under_cursor()
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
    local config = require("neojj.config")
    local ctx = cursor_context(self)

    if ctx.immutable then
      notification.warn("Cannot describe immutable commit", { dismiss = true })
      return
    end

    local change_id = ctx.change_id

    local use_editor = config.values.commit_editor.describe_editor ~= false

    if use_editor then
      -- Full editor mode (like "cd" in commit popup)
      local client = require("neojj.client")
      local builder = jj.cli.describe
      if change_id then
        builder = builder.args(change_id)
      end
      client.wrap(builder, {
        autocmd = "NeojjDescribeComplete",
        msg = {
          success = "Description updated",
          fail = "Describe failed",
        },
        show_diff = true,
        interactive = true,
        revision = change_id,
      })
    else
      -- Inline input mode
      local current_desc = ""
      if change_id then
        local result = jj.cli.log.no_graph
          .template('"" ++ description ++ ""')
          .revisions(change_id)
          .limit(1)
          .call { hidden = true, trim = true }
        if result and result.code == 0 and result.stdout[1] then
          current_desc = result.stdout[1]:gsub("\n+$", "")
        end
      else
        current_desc = jj.repo.state.head.description or ""
      end

      local short = change_id and change_id:sub(1, 8) or "change"
      local msg = input.get_user_input("Describe " .. short, { default = current_desc })
      if msg == nil then
        return
      end

      local builder = jj.cli.describe.no_edit.message(msg)
      if change_id then
        builder = builder.args("-r", change_id)
      end
      builder.call()
    end

    self:dispatch_refresh(nil, "n_describe")
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_edit_change = function(self)
  return a.void(function()
    local ctx = cursor_context(self)
    local change_id = ctx.change_id
    if not change_id then
      notification.warn("No change under cursor", { dismiss = true })
      return
    end

    if ctx.immutable then
      notification.warn("Cannot edit immutable commit", { dismiss = true })
      return
    end

    local short = change_id:sub(1, 8)
    local result = jj.cli.edit.args(change_id).call()
    if result and result.code == 0 then
      notification.info("Now editing " .. short, { dismiss = true })
      self:dispatch_refresh(nil, "n_edit_change")
    else
      local stderr = result and result.stderr
      if type(stderr) == "table" then
        stderr = table.concat(stderr, "\n")
      end
      local msg = "Failed to edit " .. short
      if stderr and stderr ~= "" then
        msg = msg .. ": " .. stderr
      end
      notification.warn(msg, { dismiss = true })
    end
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

---@param self StatusBuffer
---@return fun(): nil
M.n_undo = function(self)
  return a.void(function()
    if input.get_permission("Undo last operation?") then
      jj.cli.undo.call()
      notification.info("Undone")
      self:dispatch_refresh(nil, "n_undo")
    end
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_forget_bookmark = function(self)
  return a.void(function()
    local ctx = cursor_context(self)
    if ctx.section ~= "bookmarks" or not ctx.item or not ctx.item.name then
      notification.warn("No bookmark under cursor", { dismiss = true })
      return
    end

    local item = ctx.item
    if item.remote and item.remote ~= "" then
      -- Track remote bookmark
      local ref = item.name .. "@" .. item.remote
      if not input.get_permission("Track bookmark " .. ref .. "?") then
        return
      end
      local result = jj.cli.bookmark_track.args(ref).call()
      if result and result.code == 0 then
        local picker_cache = require("neojj.lib.picker_cache")
        picker_cache.invalidate_bookmarks()
        notification.info("Tracking " .. ref, { dismiss = true })
        self:dispatch_refresh(nil, "n_forget_bookmark")
      else
        notification.warn("Failed to track " .. ref, { dismiss = true })
      end
      return
    end

    if not input.get_permission("Forget bookmark " .. item.name .. "?") then
      return
    end

    local result = jj.cli.bookmark_forget.args(item.name).call()
    if result and result.code == 0 then
      local picker_cache = require("neojj.lib.picker_cache")
      picker_cache.invalidate_bookmarks()
      notification.info("Forgot bookmark " .. item.name, { dismiss = true })
      self:dispatch_refresh(nil, "n_forget_bookmark")
    else
      notification.warn("Failed to forget bookmark " .. item.name, { dismiss = true })
    end
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_new_change_on = function(self)
  return a.void(function()
    local ctx = cursor_context(self)
    local change_id = ctx.change_id
    if not change_id then
      notification.warn("No change under cursor", { dismiss = true })
      return
    end

    -- Auto-track untracked remote bookmarks
    local item = ctx.item
    if item and item.remote and item.remote ~= "" and ctx.section == "bookmarks" then
      local ref = item.name .. "@" .. item.remote
      local track_result = jj.cli.bookmark_track.args(ref).call()
      if track_result and track_result.code == 0 then
        local picker_cache = require("neojj.lib.picker_cache")
        picker_cache.invalidate_bookmarks()
        notification.info("Tracked " .. ref, { dismiss = true })
      end
    end

    local short = change_id:sub(1, 8)
    local result = jj.cli.new.revisions(change_id).call()
    if result and result.code == 0 then
      local picker_cache = require("neojj.lib.picker_cache")
      picker_cache.invalidate_revisions()
      notification.info("Created new change on " .. short, { dismiss = true })
      self:dispatch_refresh(nil, "n_new_change_on")
    else
      notification.warn("Failed to create change on " .. short, { dismiss = true })
    end
  end)
end

---@param self StatusBuffer
---@return fun(): nil
M.n_new_change_before = function(self)
  return a.void(function()
    local ctx = cursor_context(self)
    local change_id = ctx.change_id
    if not change_id then
      notification.warn("No change under cursor", { dismiss = true })
      return
    end

    local short = change_id:sub(1, 8)
    local result = jj.cli.new.insert_before.revisions(change_id).call()
    if result and result.code == 0 then
      local picker_cache = require("neojj.lib.picker_cache")
      picker_cache.invalidate_revisions()
      notification.info("Created new change before " .. short, { dismiss = true })
      self:dispatch_refresh(nil, "n_new_change_before")
    else
      notification.warn("Failed to create change before " .. short, { dismiss = true })
    end
  end)
end

---@param _self StatusBuffer
---@return fun(): nil
M.n_undo_popup = function(_self)
  return popups.open("undo")
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
    local ref = self.buffer.ui:get_commit_under_cursor()
      or self.buffer.ui:get_yankable_under_cursor()
    p {
      section = { name = section and section.name },
      item = { name = ref },
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

    local ref = self.buffer.ui:get_commit_under_cursor()
      or self.buffer.ui:get_yankable_under_cursor()

    p {
      bookmark = {},
      change = {},
      commit = {},
      diff = {
        section = { name = section_name },
        item = { name = ref },
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

---@param _self StatusBuffer
---@return fun(): nil
M.n_workspace_popup = function(_self)
  return popups.open("workspace")
end

---@param self StatusBuffer
---@return fun(): nil
M.n_open_in_browser = function(self)
  return function()
    local ctx = cursor_context(self)

    -- Helper to resolve remote URL
    local function get_remote_browser_url()
      local shell = require("neojj.lib.jj.shell")
      local remote_lines, code = shell.exec(
        { "jj", "--no-pager", "--color=never", "git", "remote", "list" },
        jj.repo.state.worktree_root
      )
      if code ~= 0 or not remote_lines or #remote_lines == 0 then
        return nil
      end

      local remote_url
      for _, line in ipairs(remote_lines) do
        local url = line:match("^%S+%s+(%S+)")
        if url then
          remote_url = url
          break
        end
      end

      if not remote_url then return nil end

      return remote_url
        :gsub("%.git$", "")
        :gsub("^git@([^:]+):", "https://%1/")
        :gsub("^ssh://git@([^/]+)/", "https://%1/")
    end

    -- Project header: open repo URL directly
    if ctx.yank == "__project__" then
      local browser_url = get_remote_browser_url()
      if not browser_url then
        notification.warn("No remote found", { dismiss = true })
        return
      end
      vim.ui.open(browser_url)
      return
    end

    local change_id = ctx.change_id or jj.repo.state.head.change_id

    if not change_id or change_id == "" then
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

    local browser_url = get_remote_browser_url()
    if not browser_url then
      notification.warn("No remote found", { dismiss = true })
      return
    end

    -- Construct commit URL (works for GitHub, GitLab, etc.)
    browser_url = browser_url .. "/commit/" .. commit_hash

    vim.ui.open(browser_url)
  end
end

return M
