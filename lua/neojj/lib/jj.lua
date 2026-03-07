---@class NeoJJLib
---@field repo    NeoJJRepo
---@field cli     NeoJJCLI
---@field status  NeoJJStatus
---@field log     NeoJJLog
---@field diff    NeoJJDiff
---@field bookmark NeoJJBookmark
local JJ = {}

setmetatable(JJ, {
  __index = function(_, k)
    if k == "repo" then
      return require("neojj.lib.jj.repository").instance()
    else
      return require("neojj.lib.jj." .. k)
    end
  end,
})

return JJ
