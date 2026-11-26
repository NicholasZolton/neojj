local M = {}

---Expand jj's compact rename/copy display path into destination and source paths.
---@param name string
---@param mode string
---@return string name
---@return string|nil original_name
function M.parse(name, mode)
  if mode == "R" or mode == "C" then
    local prefix, from, to, suffix = name:match("^(.-){([^{}]-) => ([^{}]-)}(.*)$")
    if prefix then
      return prefix .. to .. suffix, prefix .. from .. suffix
    end
  end
  return name, nil
end

return M
