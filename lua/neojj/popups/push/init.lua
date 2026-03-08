local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.push.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjPushPopup")
    :switch("d", "dry-run", "Dry run")
    :switch("D", "deleted", "Push deleted bookmarks")
    :group_heading("Push")
    :action("b", "Bookmark", actions.push_bookmark)
    :action("c", "Change", actions.push_change)
    :action("a", "All bookmarks", actions.push_all)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
