local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.commit.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJCommitPopup")
    :group_heading("Create")
    :action("c", "New change", actions.new_change)
    :new_action_group("Describe")
    :action("d", "Describe (editor)", actions.describe)
    :action("D", "Describe (message)", actions.describe_with_message)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
