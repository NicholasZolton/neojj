local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.rebase.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJRebasePopup")
    :switch("e", "skip-emptied", "Skip emptied commits")
    :group_heading("Rebase")
    :action("s", "Source onto dest", actions.source_onto)
    :action("b", "Bookmark onto dest", actions.bookmark_onto)
    :action("r", "Revision", actions.revision_onto)
    :env(env or {})
    :build()

  p:show()

  return p
end

return M
