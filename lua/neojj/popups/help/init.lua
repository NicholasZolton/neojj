local popup = require("neojj.lib.popup")
local actions = require("neojj.popups.help.actions")

local M = {}

-- TODO: Better alignment for labels, keys
function M.create(env)
  local p = popup.builder():name("NeojjHelpPopup"):group_heading("Commands")

  local popups = actions.popups(env)
  for i, cmd in ipairs(popups) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)

    if i == math.floor(#popups / 2) then
      p = p:new_action_group()
    end
  end

  p = p:new_action_group():new_action_group("Context actions")
  local ctx = actions.context()
  for _, cmd in ipairs(actions.actions()) do
    table.insert(ctx, cmd)
  end
  for i, cmd in ipairs(ctx) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
    if i == math.floor(#ctx / 2) then
      p = p:new_action_group()
    end
  end

  p = p:new_action_group():new_action_group("Essential commands")
  for _, cmd in ipairs(actions.essential()) do
    p = p:action(cmd.keys, cmd.name, cmd.fn)
  end

  p = p:build()
  p:show()

  return p
end

return M
