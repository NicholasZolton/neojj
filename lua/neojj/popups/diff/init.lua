local M = {}
local config = require("neojj.config")
local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.diff.actions")

function M.create(env)
  local diff_viewer = config.get_diff_viewer()
  local has_diff_viewer = diff_viewer ~= nil
  local has_item = env.item ~= nil

  local p = popup
    .builder()
    :name("NeoJJDiffPopup")
    :group_heading("Diff")
    :action_if(has_diff_viewer and has_item, "d", "this", actions.this)
    :action_if(has_diff_viewer, "r", "range", actions.range)
    :new_action_group()
    :action_if(has_diff_viewer, "w", "working copy", actions.working_copy)
    :new_action_group("Show")
    :action_if(has_diff_viewer, "c", "Change", actions.change)
    :env(env)
    :build()

  p:show()

  return p
end

return M
