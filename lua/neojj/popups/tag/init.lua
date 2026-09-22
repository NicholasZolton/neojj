local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.tag.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjTagPopup")
    :group_heading("Create")
    :action("t", "Tag", actions.create, { refresh = false })
    :new_action_group("Do")
    :action("m", "Move tag", actions.move, { refresh = false })
    :action("x", "Delete local tag", actions.delete, { refresh = false })
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
