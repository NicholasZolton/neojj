local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.workspace.actions")

local M = {}

function M.create(env)
  local p = popup
    .builder()
    :name("NeoJJWorkspacePopup")
    :arg_heading("Sparse Patterns")
    :switch("s", "sparse-patterns=copy", "Copy sparse patterns from current", {
      cli_prefix = "--",
      options = { "sparse-patterns=copy", "sparse-patterns=full", "sparse-patterns=empty" },
    })
    :group_heading("Create")
    :action("a", "Add workspace", actions.add)
    :action("A", "Add at revision", actions.add_at_revision)
    :action("q", "Quick add (random worktree)", actions.quick_add)
    :action("Q", "Quick add at revision", actions.quick_add_at_revision)
    :new_action_group("Manage")
    :action("f", "Forget (keep files)", actions.forget)
    :action("d", "Delete (forget + rm)", actions.delete)
    :action("r", "Rename current", actions.rename)
    :new_action_group("Info")
    :action("l", "List workspaces", actions.list)
    :action("R", "Show root", actions.root)
    :action("u", "Update stale", actions.update_stale)
    :env(env or {})
    :build()

  p:show()
  return p
end

return M
