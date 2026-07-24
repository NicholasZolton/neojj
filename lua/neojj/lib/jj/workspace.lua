local M = {}

local cli = require("neojj.lib.jj.cli")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local picker_cache = require("neojj.lib.picker_cache")

local function notify_not_workspace(path)
  notification.error(("The directory `%s` is not a jj workspace"):format(path))
end

---Prompt to initialize a jj workspace and return its root on success.
---@param dir string
---@return string|nil root
function M.prompt_init(dir)
  local path = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")

  if not input.get_permission(("Initialize jj repository in `%s`?"):format(path)) then
    notify_not_workspace(path)
    return nil
  end

  local result = cli.git_init.colocate.args(path).call { await = true }
  if not result or result.code ~= 0 then
    local message = picker_cache.error_msg(result)
    notification.error(("Failed to initialize jj repository in `%s`: %s"):format(path, message))
    return nil
  end

  cli.clear_cache()
  local root = cli.find_workspace_root(path)
  if not root then
    notification.error(("jj initialized successfully, but `%s` is not a jj workspace"):format(path))
    return nil
  end

  return root
end

return M
