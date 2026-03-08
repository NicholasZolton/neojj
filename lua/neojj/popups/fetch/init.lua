local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.fetch.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjFetchPopup")
    :group_heading("Fetch")
    :action("f", "All remotes", actions.fetch_all)
    :action("r", "From remote", actions.fetch_remote)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
