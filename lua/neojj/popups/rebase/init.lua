local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.rebase.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeojjRebasePopup")
    :arg_heading("Flags")
    :switch("e", "skip-emptied", "Skip emptied commits")
    :switch("k", "keep-divergent", "Keep divergent commits")
    :switch("S", "simplify-parents", "Simplify parents")
    :group_heading("Rebase")
    :action("h", "Here (@) onto...", actions.here_onto)
    :action("s", "Source onto dest", actions.source_onto)
    :action("b", "Bookmark onto dest", actions.bookmark_onto)
    :action("r", "Revision onto dest", actions.revision_onto)
    :new_action_group("Trunk")
    :action("t", "Stack onto trunk", actions.stack_onto_trunk)
    :action("T", "Current (@) onto trunk", actions.current_onto_trunk)
    :new_action_group("Other")
    :action("p", "Parallelize", actions.parallelize)
    :env(env or {})
    :build()

  p:show()

  return p
end

return M
