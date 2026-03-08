local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.change.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjChangePopup")
    :switch("B", "insert-before", "Insert before target")
    :switch("A", "insert-after", "Insert after target")
    :option("m", "message", "", "Description for new change")
    :group_heading("Create")
    :action("n", "New change", actions.new_change)
    :action("p", "New on parent(s)", actions.new_on_revisions)
    :action("M", "Merge", actions.merge)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
