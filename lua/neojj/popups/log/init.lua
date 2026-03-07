local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.log.actions")

local M = {}

function M.create()
  local p = popup
    .builder()
    :name("NeoJJLogPopup")
    :arg_heading("Filtering")
    :option("n", "limit", "256", "Limit number of changes", { default = "256", key_prefix = "-" })
    :option("r", "revisions", "", "Revset filter")
    :switch("g", "graph", "Show graph", { enabled = true, internal = true })
    :switch("d", "decorate", "Show bookmarks", { enabled = true, internal = true })
    :group_heading("Log")
    :action("l", "All changes", actions.log_all)
    :action("r", "Revset", actions.log_revset)
    :action("b", "Bookmark", actions.log_bookmark)
    :new_action_group("Operations")
    :action("o", "Op log", actions.op_log)
    :build()

  p:show()

  return p
end

return M
