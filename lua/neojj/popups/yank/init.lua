local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.yank.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjYankPopup")
    :group_heading("Yank Change info")
    :action("c", "Change ID", actions.change_id)
    :action("C", "Commit ID", actions.commit_id)
    :action("s", "Subject", actions.subject)
    :action("m", "Message", actions.message)
    :action("d", "Diff", actions.diff)
    :action("a", "Author", actions.author)
    :env(env)
    :build()

  p:show()
  return p
end

return M
