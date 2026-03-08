local git = require("neojj.lib.git")
local util = require("neojj.lib.util")

---@class NeojjGitCherry
local M = {}

function M.list(upstream, head)
  local result = git.cli.cherry.verbose.args(upstream, head).call({ hidden = true }).stdout
  return util.reverse(util.map(result, function(cherry)
    local status, oid, subject = cherry:match("([%+%-]) (%x+) (.*)")
    return { status = status, oid = oid, subject = subject }
  end))
end

return M
