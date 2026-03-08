local config = require("neojj.config")
local Buffer = require("neojj.lib.buffer")
local ui = require("neojj.buffers.status.ui")
local popups = require("neojj.popups")
local jj = require("neojj.lib.jj")
local Watcher = require("neojj.watcher")
local a = require("plenary.async")
local logger = require("neojj.logger") -- TODO: Add logging
local event = require("neojj.lib.event")

---@class Semaphore
---@field permits number
---@field acquire function

---@class StatusBuffer
---@field buffer Buffer instance
---@field config NeoJJConfig
---@field root string
---@field cwd string
local M = {}
M.__index = M

local instances = {}

---@class SubmoduleInfo
---@field submodules string[] A list with the relative paths to the project's submodules
---@field parent_repo string? If we are in a submodule, cache the abs path to the parent repo

---@type table<string, SubmoduleInfo>
local submodule_info_per_root = {}

---@return string?
function M:parent_repo()
  local info = submodule_info_per_root[self.root]
  return info and info.parent_repo
end

---@return string[]
function M:submodules()
  local info = submodule_info_per_root[self.root]
  return info and info.submodules or {}
end

---@param abs_path string
---@return boolean
function M:has_submodule(abs_path)
  local dir = require("plenary.path"):new(abs_path)
  if not dir:exists() or not dir:is_dir() then
    return false
  end
  local rel_path = dir:make_relative(self.cwd)
  for _, submodule in ipairs(self:submodules()) do
    if submodule == rel_path then
      return true
    end
  end
  return false
end

---@param instance StatusBuffer
---@param dir string
function M.register(instance, dir)
  local dir = vim.fs.normalize(dir)
  logger.debug("[STATUS] Registering instance for: " .. dir)

  instances[dir] = instance
  submodule_info_per_root[instance.root] = {
    submodules = {}, -- TODO: jj doesn't have submodules in the same way
    parent_repo = nil,
  }
end

---@param dir? string
---@return StatusBuffer
function M.instance(dir)
  local dir = dir or vim.uv.cwd()
  assert(dir, "cannot locate a status buffer with no cwd")

  return instances[vim.fs.normalize(dir)]
end

---@param config NeoJJConfig
---@param root string
---@param cwd string
---@return StatusBuffer
function M.new(config, root, cwd)
  if M.instance(cwd) then
    logger.debug("Found instance for cwd " .. cwd)
    return M.instance(cwd)
  end

  local instance = {
    config = config,
    root = root,
    cwd = vim.fs.normalize(cwd),
    buffer = nil,
    fold_state = nil,
    cursor_state = nil,
    view_state = nil,
  }

  setmetatable(instance, M)
  M.register(instance, cwd)

  return instance
end

---@return boolean
function M.is_open()
  return (M.instance() and M.instance().buffer and M.instance().buffer:is_visible()) == true
end

function M:_action(name)
  local action = require("neojj.buffers.status.actions")[name]
  assert(action, ("Status Buffer action %q is undefined"):format(name))

  return action(self)
end

---@param kind nil|string
---| "'floating'"
---| "'split'"
---| "'tab'"
---| "'split'"
---| "'vsplit'"
---@return StatusBuffer
function M:open(kind)
  if self.buffer and self.buffer:is_visible() then
    logger.debug("[STATUS] An Instance is already open - focusing it")
    self.buffer:focus()
    return self
  end

  local mappings = config.get_reversed_status_maps()

  self.buffer = Buffer.create {
    name = "NeoJJStatus",
    filetype = "NeoJJStatus",
    cwd = self.cwd,
    context_highlight = not config.values.disable_context_highlighting,
    kind = kind or config.values.kind or "tab",
    disable_line_numbers = config.values.disable_line_numbers,
    disable_relative_line_numbers = config.values.disable_relative_line_numbers,
    foldmarkers = not config.values.disable_signs,
    active_item_highlight = true,
    on_detach = function()
      Watcher.instance(self.root):unregister(self)

      if self.prev_autochdir then
        vim.o.autochdir = self.prev_autochdir
      end
    end,
    --stylua: ignore start
    mappings = {
      v = {
        [mappings["Discard"]]                   = self:_action("v_discard"),
        [popups.mapping_for("DiffPopup")]       = self:_action("v_diff_popup"),
        [popups.mapping_for("HelpPopup")]       = self:_action("v_help_popup"),
        [popups.mapping_for("LogPopup")]        = self:_action("v_log_popup"),
      },
      n = {
        [mappings["Command"]]                   = self:_action("n_command"),
        [mappings["MoveDown"]]                  = self:_action("n_down"),
        [mappings["MoveUp"]]                    = self:_action("n_up"),
        [mappings["Toggle"]]                    = self:_action("n_toggle"),
        [mappings["OpenFold"]]                  = self:_action("n_open_fold"),
        [mappings["CloseFold"]]                 = self:_action("n_close_fold"),
        [mappings["Close"]]                     = self:_action("n_close"),
        [mappings["OpenOrScrollDown"]]          = self:_action("n_open_or_scroll_down"),
        [mappings["OpenOrScrollUp"]]            = self:_action("n_open_or_scroll_up"),
        [mappings["RefreshBuffer"]]             = self:_action("n_refresh_buffer"),
        [mappings["Depth1"]]                    = self:_action("n_depth1"),
        [mappings["Depth2"]]                    = self:_action("n_depth2"),
        [mappings["Depth3"]]                    = self:_action("n_depth3"),
        [mappings["Depth4"]]                    = self:_action("n_depth4"),
        [mappings["CommandHistory"]]            = self:_action("n_command_history"),
        [mappings["YankSelected"]]              = self:_action("n_yank_commit_hash"),
        [mappings["ShowRefs"]]                  = self:_action("n_yank_selected"),
        [mappings["Discard"]]                   = self:_action("n_discard"),
        [mappings["GoToNextHunkHeader"]]        = self:_action("n_go_to_next_hunk_header"),
        [mappings["GoToPreviousHunkHeader"]]    = self:_action("n_go_to_previous_hunk_header"),
        [mappings["GoToFile"]]                  = self:_action("n_goto_file"),
        [mappings["TabOpen"]]                   = self:_action("n_tab_open"),
        [mappings["SplitOpen"]]                 = self:_action("n_split_open"),
        [mappings["VSplitOpen"]]                = self:_action("n_vertical_split_open"),
        [mappings["NextSection"]]               = self:_action("n_next_section"),
        [mappings["PreviousSection"]]           = self:_action("n_prev_section"),
        -- jj-specific actions
        ["D"]                                   = self:_action("n_describe"),
        ["N"]                                   = self:_action("n_new_change"),
        ["A"]                                   = self:_action("n_abandon"),
        ["o"]                                   = self:_action("n_open_in_browser"),
        ["x"]                                   = self:_action("n_context_delete"),
        -- jj popup bindings
        [popups.mapping_for("CommitPopup")]     = self:_action("n_commit_popup"),
        [popups.mapping_for("DiffPopup")]       = self:_action("n_diff_popup"),
        [popups.mapping_for("FetchPopup")]      = self:_action("n_fetch_popup"),
        [popups.mapping_for("HelpPopup")]       = self:_action("n_help_popup"),
        [popups.mapping_for("LogPopup")]        = self:_action("n_log_popup"),
        [popups.mapping_for("PushPopup")]       = self:_action("n_push_popup"),
        [popups.mapping_for("RebasePopup")]     = self:_action("n_rebase_popup"),
        [popups.mapping_for("RemotePopup")]     = self:_action("n_remote_popup"),
        [popups.mapping_for("SquashPopup")]     = self:_action("n_squash_popup"),
        [popups.mapping_for("UndoPopup")]      = self:_action("n_undo_popup"),
        [popups.mapping_for("WorkspacePopup")] = self:_action("n_workspace_popup"),
        ["b"]                                   = self:_action("n_bookmark_popup"),
        ["V"]                                   = function()
          vim.cmd("norm! V")
        end,
      },
    },
    --stylua: ignore end
    user_mappings = config.get_user_mappings("status"),
    initialize = function()
      self.prev_autochdir = vim.o.autochdir
      vim.o.autochdir = false
    end,
    render = function()
      return ui.Status(jj.repo.state, self.config)
    end,
    ---@param buffer Buffer
    ---@param _win any
    after = function(buffer, _win)
      Watcher.instance(self.root):register(self)
      buffer:move_cursor(buffer.ui:first_section().first)
    end,
    user_autocmds = {
      -- Resetting doesn't yield the correct repo state instantly, so we need to re-refresh after a few seconds
      -- in order to show the user the correct state.
      ["NeoJJReset"] = self:deferred_refresh("reset"),
      ["NeoJJBranchReset"] = self:deferred_refresh("reset_branch"),
    },
    autocmds = {
      ["FocusGained"] = self:deferred_refresh("focused", 10),
    },
  }

  return self
end

function M:close()
  if self.buffer then
    self.fold_state = self.buffer.ui:get_fold_state()
    self.cursor_state = self.buffer:cursor_line()
    self.view_state = self.buffer:save_view()

    logger.debug("[STATUS] Closing Buffer")
    self.buffer:close()
    self.buffer = nil
  end
end

function M:chdir(dir)
  local Path = require("plenary.path")

  local destination = Path:new(dir)
  vim.wait(5000, function()
    return destination:exists()
  end)

  vim.schedule(function()
    logger.debug("[STATUS] Changing Dir: " .. dir)
    vim.api.nvim_set_current_dir(dir)
    require("neojj.lib.jj.repository").instance(dir)
    self.new(config.values, jj.repo.worktree_root, dir):open("replace"):dispatch_refresh()
  end)
end

function M:focus()
  if self.buffer then
    logger.debug("[STATUS] Focusing Buffer")
    self.buffer:focus()
  end
end

function M:refresh(partial, reason)
  logger.debug("[STATUS] Beginning refresh from " .. (reason or "UNKNOWN"))

  -- Needs to be captured _before_ refresh because the diffs are needed, but will be changed by refreshing.
  local cursor, view
  if self.buffer and self.buffer:is_focused() then
    cursor = self.buffer.ui:get_cursor_location()
    view = self.buffer:save_view()
  end

  jj.repo:dispatch_refresh {
    source = "status",
    partial = partial,
    callback = function()
      self:redraw(cursor, view)
      event.send("StatusRefreshed")
      logger.info("[STATUS] Refresh complete")
    end,
  }
end

---@param cursor CursorLocation?
---@param view table?
function M:redraw(cursor, view)
  if not self.buffer then
    logger.debug("[STATUS] Buffer no longer exists - bail")
    return
  end

  logger.debug("[STATUS] Rendering UI")
  self.buffer.ui:render(unpack(ui.Status(jj.repo.state, self.config)))

  if self.fold_state and self.buffer then
    logger.debug("[STATUS] Restoring fold state")
    self.buffer.ui:set_fold_state(self.fold_state)
    self.fold_state = nil
  end

  if self.cursor_state and self.view_state and self.buffer then
    logger.debug("[STATUS] Restoring cursor and view state")
    self.buffer:restore_view(self.view_state, self.cursor_state)
    self.view_state = nil
    self.cursor_state = nil
  elseif cursor and view and self.buffer then
    self.buffer:restore_view(view, self.buffer.ui:resolve_cursor_location(cursor))
  end
end

M.dispatch_refresh = a.void(function(self, partial, reason)
  self:refresh(partial, reason)
end)

---@param reason string
---@param wait number? timeout in ms, or 2 seconds
---@return fun()
function M:deferred_refresh(reason, wait)
  return function()
    vim.defer_fn(function()
      self:dispatch_refresh(nil, reason)
    end, wait or 2000)
  end
end

function M:reset()
  logger.debug("[STATUS] Resetting repo and refreshing - CWD: " .. vim.uv.cwd())
  jj.repo:reset()
  self:refresh(nil, "reset")
end

M.dispatch_reset = a.void(function(self)
  self:reset()
end)

function M:id()
  return "StatusBuffer"
end

return M
