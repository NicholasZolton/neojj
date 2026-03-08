local M = {}

local jj = require("neojj.lib.jj")
local notification = require("neojj.lib.notification")
local input = require("neojj.lib.input")
local picker_cache = require("neojj.lib.picker_cache")

function M.fetch_all(_popup)
  notification.info("Fetching from all remotes")
  local result = jj.cli.git_fetch.all_remotes.call()
  if result and result.code == 0 then
    notification.info("Fetched from all remotes", { dismiss = true })
  else
    notification.warn("Fetch failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.fetch_remote(_popup)
  local remote = input.get_user_input("Remote name", { default = "origin" })
  if not remote or remote == "" then
    return
  end

  notification.info("Fetching from " .. remote)
  local result = jj.cli.git_fetch.remote(remote).call()
  if result and result.code == 0 then
    notification.info("Fetched from " .. remote, { dismiss = true })
  else
    notification.warn("Fetch failed: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

return M
