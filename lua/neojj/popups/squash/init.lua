local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.squash.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjSquashPopup")
    :arg_heading("Flags")
    :switch("i", "interactive", "Select changes interactively")
    :switch("k", "keep-emptied", "Keep emptied source revision")
    :switch("u", "use-destination-message", "Use destination's description")
    :group_heading("Squash")
    :action("s", "into parent", actions.squash)
    :action("S", "into revision", actions.squash_into)
    :action("r", "Revision into its parent", actions.squash_revision)
    :action("R", "Range into revision", actions.squash_range)
    :new_action_group("Absorb")
    :action("a", "Absorb into prior changes", actions.absorb)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
