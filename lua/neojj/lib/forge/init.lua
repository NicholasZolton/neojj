---Forge integration: matches local bookmarks to open PRs on a remote
---forge (GitHub today; other providers slot into the registry below).
---
---A provider supplies its identity and CLI; everything else — host
---resolution, gating, the async fetch, and the per-root cache — lives here
---and is provider-agnostic.

---@class neojj.ForgePR
---@field number integer
---@field title string
---@field url string
---@field branch string Head ref name, matched against bookmark names
---@field draft boolean

---@class neojj.Forge
---@field name string
---@field executable string CLI binary the provider shells out to
---@field default_hosts string[]
---@field pr_list_cmd string[] Command listing open PRs as JSON on stdout
---@field parse_prs fun(stdout: string|nil): neojj.ForgePR[]|nil

local logger = require("neojj.logger")

local M = {}

---@type neojj.Forge[]
local providers = {
  require("neojj.lib.forge.github"),
}

---@class neojj.ForgeCacheEntry
---@field index table<string, neojj.ForgePR>|nil
---@field failed boolean|nil Fetch failed once; don't retry this session
---@field in_flight boolean|nil

---@type table<string, neojj.ForgeCacheEntry>
local cache = {}

---Resolve the provider responsible for a remote host.
---@param host string|nil
---@param extra_hosts table<string, string[]>|nil Additional hosts per provider name (e.g. GitHub Enterprise)
---@return neojj.Forge|nil
function M.provider_for_host(host, extra_hosts)
  if not host then
    return nil
  end

  for _, provider in ipairs(providers) do
    local hosts = vim.deepcopy(provider.default_hosts)
    vim.list_extend(hosts, extra_hosts and extra_hosts[provider.name] or {})
    if vim.tbl_contains(hosts, host) then
      return provider
    end
  end

  return nil
end

---Index PRs by head branch name; first PR wins on collision.
---@param prs neojj.ForgePR[]
---@return table<string, neojj.ForgePR>
function M.build_index(prs)
  local index = {}
  for _, pr in ipairs(prs) do
    if index[pr.branch] == nil then
      index[pr.branch] = pr
    end
  end

  return index
end

---@param root string
---@param branch string|nil
---@return neojj.ForgePR|nil
function M.pr_for_branch(root, branch)
  local entry = cache[root]
  if not (entry and entry.index and branch) then
    return nil
  end

  return entry.index[branch]
end

---@param root string|nil Reset one root, or all when nil
function M.reset(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

---Test seam: install a prebuilt index for a root.
---@param root string
---@param index table<string, neojj.ForgePR>
function M._set_index(root, index)
  cache[root] = { index = index }
end

---Fetch open PRs for a worktree root if the integration is enabled, the
---provider CLI is installed, and the remote host matches a provider.
---Failures are silent and remembered: this never retries within a session,
---and `callback` runs (on the main loop) only when fresh data arrives.
---@param root string
---@param callback fun()|nil
function M.refresh(root, callback)
  local forge_config = require("neojj.config").values.forge
  if not (forge_config and forge_config.pr_integration) then
    return
  end

  local entry = cache[root]
  if entry and (entry.failed or entry.in_flight) then
    return
  end

  local info = require("neojj.lib.jj.remote").get(root)
  local provider = info and M.provider_for_host(info.host, forge_config.hosts)
  if not provider or vim.fn.executable(provider.executable) ~= 1 then
    cache[root] = { failed = true }
    return
  end

  cache[root] = { in_flight = true, index = entry and entry.index }
  vim.system(provider.pr_list_cmd, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        logger.debug("[FORGE] " .. provider.name .. " pr list failed: " .. (result.stderr or ""))
        cache[root] = { failed = true }
        return
      end

      local prs = provider.parse_prs(result.stdout)
      if not prs then
        logger.debug("[FORGE] " .. provider.name .. " pr list output unparsable")
        cache[root] = { failed = true }
        return
      end

      cache[root] = { index = M.build_index(prs) }
      if callback then
        callback()
      end
    end)
  end)
end

return M
