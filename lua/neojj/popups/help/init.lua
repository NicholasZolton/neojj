local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.help.actions")

local M = {}

-- TODO: Better alignment for labels, keys
function M.create(env)
  env = env or {}
  local context = env.context or {}
  local p = popup.builder():name("NeojjHelpPopup"):group_heading("Commands")

  local popups = actions.popups(env)
  for i, cmd in ipairs(popups) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)

    if i == math.floor(#popups / 2) then
      p = p:new_action_group()
    end
  end

  p = p:new_action_group():new_action_group("Revisions (cursor)")
  for _, cmd in ipairs(actions.revisions(context)) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:group_heading("Bookmarks (cursor)")
  for _, cmd in ipairs(actions.bookmarks(context)) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:new_action_group("Selected changes (files)")
  for _, cmd in ipairs(actions.selection(context)) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:new_action_group():new_action_group("Navigation")
  for _, cmd in ipairs(actions.navigation()) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:build()
  p:show()

  return p
end

return M
