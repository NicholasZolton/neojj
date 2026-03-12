local M = {}
local util = require("neojj.lib.util")
local NONE = function() end

local status_mappings = require("neojj.config").get_reversed_status_maps()
local popup_mappings = require("neojj.config").get_reversed_popup_maps()

local function present(commands)
  local presenter = util.map(commands, function(command)
    local cmd, name, fn = unpack(command)
    if type(fn) == "table" then fn = fn[2] end

    local keymap = status_mappings[cmd]
    if not keymap or keymap == "<nop>" then
      keymap = popup_mappings[cmd]
    end

    if type(keymap) == "table" and next(keymap) then
      table.sort(keymap)
      if name == "Toggle" and keymap[2] == "za" then
        table.remove(keymap, 2)
      end
      return { { name = name, keys = keymap, cmp = table.concat(keymap):lower(), fn = fn } }
    else
      return { { name = name, keys = {}, cmp = "", fn = fn } }
    end
  end)

  presenter = util.flatten(presenter)
  table.sort(presenter, function(a, b)
    return a.cmp < b.cmp
  end)

  return presenter
end

M.popups = function(env)
  local popups = require("neojj.popups")
  local items = {
    { "CommandHistory", "History", function()
      require("neojj.buffers.command_history"):new():show()
    end },
    { "DiffPopup", "Diff", popups.open("diff", function(p) p(env.diff or {}) end) },
    { "RebasePopup", "Rebase", popups.open("rebase", function(p) p(env.rebase or {}) end) },
    { "PushPopup", "Push", popups.open("push", function(p) p(env.push or {}) end) },
    { "CommitPopup", "Change", popups.open("commit", function(p) p(env.commit or {}) end) },
    { "LogPopup", "Log", popups.open("log", function(p) p(env.log or {}) end) },
    { "FetchPopup", "Fetch", popups.open("fetch", function(p) p(env.fetch or {}) end) },
    { "BookmarkPopup", "Bookmark", popups.open("bookmark", function(p) p(env.bookmark or {}) end) },
    { "SquashPopup", "Squash", popups.open("squash", function(p) p(env.squash or {}) end) },
    { "UndoPopup", "Undo", popups.open("undo", function(p) p(env.undo or {}) end) },
    { "RemotePopup", "Remote", popups.open("remote", function(p) p(env.remote or {}) end) },
    { "WorkspacePopup", "Workspace", popups.open("workspace", function(p) p(env.workspace or {}) end) },
    { "Command", "Command", require("neojj.buffers.status.actions").n_command(nil) },
  }

  return present(items)
end

M.actions = function()
  return present {
    { "Discard", "Discard", NONE },
  }
end

M.context = function()
  return {
    { name = "Describe", keys = { "D" }, fn = NONE },
    { name = "Edit change", keys = { "E" }, fn = NONE },
    { name = "New change", keys = { "N" }, fn = NONE },
    { name = "New change on", keys = { "O" }, fn = NONE },
    { name = "New change before", keys = { "B" }, fn = NONE },
    { name = "Abandon", keys = { "A" }, fn = NONE },
    { name = "Forget bookmark", keys = { "F" }, fn = NONE },
    { name = "Open in browser", keys = { "o" }, fn = NONE },
  }
end

M.essential = function()
  return present {
    { "RefreshBuffer", "Refresh", function()
      local status = require("neojj.buffers.status")
      if status.is_open() then
        status.instance():dispatch_refresh(nil, "user_refresh")
      end
    end },
    { "GoToFile", "Go to file", NONE },
    { "Toggle", "Toggle", NONE },
  }
end

return M
