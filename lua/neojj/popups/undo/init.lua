local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.undo.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjUndoPopup")
    :group_heading("Undo")
    :action("u", "Undo last operation", actions.undo)
    :action("r", "Redo last undo", actions.redo)
    :action("o", "Restore to operation...", actions.op_restore)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
