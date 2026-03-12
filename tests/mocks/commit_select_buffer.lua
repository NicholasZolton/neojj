local CommitSelectViewBuffer = require("neojj.buffers.commit_select_view")

local M = {
  values = {},
}

---Add a rev name to the mocked list of commits the user selected.
---@param rev string the rev name of the commit which the user will select once `CommitSelectViewBuffer:open_async()` is called
function M.add(rev)
  table.insert(M.values, rev)
end

---Clear the table
function M.clear()
  M.values = {}
end

CommitSelectViewBuffer.open_async = function()
  return M.values
end

return M
