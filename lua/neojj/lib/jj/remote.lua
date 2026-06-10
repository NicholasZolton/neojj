---@class neojj.RemoteInfo
---@field host string
---@field browser_url string

local M = {}

---@type table<string, neojj.RemoteInfo|false>
local cache = {}

---Normalize a git remote URL into its host and https browser URL.
---@param url string|nil
---@return neojj.RemoteInfo|nil
function M.parse(url)
  if type(url) ~= "string" then
    return nil
  end

  local https =
    url:gsub("%.git$", ""):gsub("^git@([^:]+):", "https://%1/"):gsub("^ssh://git@([^/]+)/", "https://%1/")

  local host = https:match("^https?://([^/]+)/.")
  if not host then
    return nil
  end

  return { host = host, browser_url = https }
end

---Resolve the first git remote for a worktree root, cached per root.
---@param root string
---@return neojj.RemoteInfo|nil
function M.get(root)
  if cache[root] ~= nil then
    return cache[root] or nil
  end

  local shell = require("neojj.lib.jj.shell")
  local lines, code = shell.exec({ "jj", "--no-pager", "--color=never", "git", "remote", "list" }, root)

  local info
  if code == 0 and lines then
    for _, line in ipairs(lines) do
      local url = line:match("^%S+%s+(%S+)")
      if url then
        info = M.parse(url)
        break
      end
    end
  end

  cache[root] = info or false
  return info
end

---@param root string|nil Invalidate one root, or all when nil
function M.invalidate(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

return M
