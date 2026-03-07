local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.remote.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJRemotePopup")
    :group_heading("Actions")
    :action("a", "Add", actions.add)
    :action("r", "Rename", actions.rename)
    :action("x", "Remove", actions.remove)
    :action("l", "List", actions.list)
    :env(env or {})
    :build()

  p:show()

  return p
end

return M
