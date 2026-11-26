local M = {}

---Expand jj's compact rename/copy display path into destination and source paths.
---@param name string
---@param mode string
---@param original_name? string Already expanded source path
---@return string name
---@return string|nil original_name
function M.parse(name, mode, original_name)
  if original_name then
    return name, original_name
  end
  if mode == "R" or mode == "C" then
    local prefix, from, to, suffix = name:match("^(.-){([^{}]-) => ([^{}]-)}(.*)$")
    if prefix then
      return prefix .. to .. suffix, prefix .. from .. suffix
    end
  end
  return name, nil
end

return M
