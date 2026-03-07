local notification = require("neojj.lib.notification")
local M = {}

local function yank(key)
  return function(popup)
    local data = popup:get_env(key)
    if data then
      vim.cmd.let(("@+='%s'"):format(data))
      notification.info(("Copied %s to clipboard."):format(key))
    end
  end
end

M.change_id = yank("change_id")
M.commit_id = yank("commit_id")
M.subject = yank("subject")
M.message = yank("message")
M.diff = yank("diff")
M.author = yank("author")

return M
