---@class NeoJJGitLib
---@field repo        NeoJJRepo
---@field branch      table
---@field cherry      table
---@field cli         table
---@field config      table
---@field diff        table
---@field fetch       table
---@field files       table
---@field hooks       table
---@field init        table
---@field log         table
---@field push        table
---@field rebase      table
---@field refs        table
---@field remote      table
---@field rev_parse   table
---@field sequencer   table
---@field status      table
---@field submodule   table
local Git = {}

setmetatable(Git, {
  __index = function(_, k)
    if k == "repo" then
      return require("neojj.lib.git.repository").instance()
    else
      return require("neojj.lib.git." .. k)
    end
  end,
})

return Git
