local M = {}
local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local picker_cache = require("neojj.lib.picker_cache")

function M.add(_popup)
  local name = input.get_user_input("Remote name")
  if not name or name == "" then return end

  local url = input.get_user_input("URL for " .. name)
  if not url or url == "" then return end

  local result = jj.cli.git_remote_add.args(name, url).call()
  if result and result.code == 0 then
    notification.info("Added remote " .. name, { dismiss = true })
  else
    notification.warn("Failed to add remote: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.rename(_popup)
  local old = input.get_user_input("Rename remote")
  if not old or old == "" then return end

  local new = input.get_user_input("Rename '" .. old .. "' to")
  if not new or new == "" then return end

  local result = jj.cli.git_remote_rename.args(old, new).call()
  if result and result.code == 0 then
    notification.info("Renamed '" .. old .. "' to '" .. new .. "'", { dismiss = true })
  else
    notification.warn("Failed to rename remote: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.remove(_popup)
  local name = input.get_user_input("Remove remote")
  if not name or name == "" then return end

  if not input.get_permission(("Remove remote '%s'?"):format(name)) then return end

  local result = jj.cli.git_remote_remove.args(name).call()
  if result and result.code == 0 then
    notification.info("Removed remote " .. name, { dismiss = true })
  else
    notification.warn("Failed to remove remote: " .. picker_cache.error_msg(result), { dismiss = true })
  end
end

function M.list(_popup)
  local result = jj.cli.git_remote_list.call { hidden = true, trim = true }
  if result and result.code == 0 then
    local msg = table.concat(result.stdout, "\n")
    if msg == "" then
      notification.info("No remotes configured")
    else
      notification.info("Remotes:\n" .. msg)
    end
  end
end

return M
