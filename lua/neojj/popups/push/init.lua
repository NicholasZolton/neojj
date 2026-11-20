local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.push.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjPushPopup")
    :switch("d", "dry-run", "Dry run")
    :switch("D", "deleted", "Push deleted bookmarks")
    :switch("r", "remote", "Push to a specific remote", { internal = true })
    :group_heading("Push")
    :action("p", "Tracking", actions.push)
    :action("b", "Bookmark", actions.push_bookmark)
    :action("c", "Change", actions.push_change)
    :action("a", "All bookmarks", actions.push_all)
    :action("T", "Tag", actions.push_tag, { refresh = false })
    :action("t", "All tags", actions.push_all_tags, { refresh = false })
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
