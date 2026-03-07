local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.resolve.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJResolvePopup")
    :option("t", "tool", "", "Merge tool")
    :group_heading("Resolve")
    :action("r", "Resolve conflicts", actions.resolve)
    :action("l", "List conflicts", actions.list)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
