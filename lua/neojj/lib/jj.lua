---@class NeojjLib
---@field repo    NeojjRepo
---@field cli     NeojjCLI
---@field status  NeojjStatus
---@field log     NeojjLog
---@field diff    NeojjDiff
---@field bookmark NeojjBookmark
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
