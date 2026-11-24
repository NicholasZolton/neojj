local M = {}

---Quote a workspace-relative path for an exact jj fileset match.
---@param path string
---@return string
function M.root_file(path)
  -- jj doesn't accept the slash escape emitted by Neovim 0.10's JSON encoder.
  local quoted = path:gsub('[\\"]', "\\%0")
  return 'root-file:"' .. quoted .. '"'
end

return M
