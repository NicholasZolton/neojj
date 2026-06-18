---@class neojj.RemoteInfo
---@field host string
---@field browser_url string
---@field slug string Repo path on the host, e.g. "owner/repo"

local M = {}

---Normalize a git remote URL into its host and https browser URL.
---@param url string|nil
---@return neojj.RemoteInfo|nil
function M.parse(url)
  if type(url) ~= "string" then
    return nil
  end

  local https =
    url:gsub("%.git$", ""):gsub("^git@([^:]+):", "https://%1/"):gsub("^ssh://git@([^/]+)/", "https://%1/")

  local host, slug = https:match("^https?://([^/]+)/(.+)$")
  if not host then
    return nil
  end

  return { host = host, browser_url = https, slug = slug }
end

---Resolve the first git remote for a worktree root.
---@param root string
---@return neojj.RemoteInfo|nil
function M.get(root)
  local shell = require("neojj.lib.jj.shell")
  local lines, code = shell.exec({ "jj", "--no-pager", "--color=never", "git", "remote", "list" }, root)

  if code ~= 0 or not lines then
    return nil
  end

  for _, line in ipairs(lines) do
    local url = line:match("^%S+%s+(%S+)")
    if url then
      return M.parse(url)
    end
  end

  return nil
end

return M
