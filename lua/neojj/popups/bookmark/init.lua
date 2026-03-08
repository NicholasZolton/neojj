local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.bookmark.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjBookmarkPopup")
    :switch("B", "allow-backwards", "Allow moving bookmark backwards")
    :group_heading("Create")
    :action("c", "Create", actions.create)
    :action("s", "Set (create or update)", actions.set)
    :new_action_group("Do")
    :action("m", "Move to revision", actions.move)
    :action("r", "Rename", actions.rename)
    :action("a", "Advance", actions.advance)
    :new_action_group("Remove")
    :action("d", "Delete", actions.delete)
    :action("f", "Forget", actions.forget)
    :new_action_group("Remote")
    :action("t", "Track", actions.track)
    :action("u", "Untrack", actions.untrack)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
