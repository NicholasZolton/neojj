local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.split.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJSplitPopup")
    :switch("i", "interactive", "Select changes interactively")
    :group_heading("Split")
    :action("s", "Working copy", actions.split_current)
    :action("r", "Revision", actions.split_revision)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
