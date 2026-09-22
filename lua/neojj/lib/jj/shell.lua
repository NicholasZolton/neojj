--- Resolve the real jj binary path (bypassing mise/asdf shims).
--- Mise shims add ~750ms per invocation. The real binary is ~50ms.
--- We resolve the path once by checking mise's install directory, then cache it.

local M = {}

---@type string|nil
local resolved_jj_path = nil

---Find real jj binary by checking mise installs directory
---@return string|nil
local function find_mise_jj()
  local mise_dir = vim.env.HOME .. "/.local/share/mise/installs/jj"
  local stat = vim.uv.fs_stat(mise_dir)
  if not stat then
    return nil
  end

  -- Try "latest" symlink first, then find highest version
  local latest = mise_dir .. "/latest/jj"
  if vim.uv.fs_stat(latest) then
    local real = vim.uv.fs_realpath(latest)
    return real or latest
  end

  -- Fallback: scan for version directories
  local handle = vim.uv.fs_scandir(mise_dir)
  if not handle then
    return nil
  end

  local best_version, best_path = nil, nil
  while true do
    local name, ftype = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if ftype == "directory" and name:match("^%d") then
      local candidate = mise_dir .. "/" .. name .. "/jj"
      if vim.uv.fs_stat(candidate) then
        if not best_version or name > best_version then
          best_version = name
          best_path = candidate
        end
      end
    end
  end

  return best_path
end

---Resolve the real jj binary path
---@return string path to jj binary
function M.resolve_jj()
  if resolved_jj_path then
    return resolved_jj_path
  end

  -- Check user config first
  local ok, config = pcall(require, "neojj.config")
  if ok and config.values and config.values.jj_binary and config.values.jj_binary ~= "auto" then
    resolved_jj_path = config.values.jj_binary
    return resolved_jj_path --[[@as string]]
  end

  -- Auto-detect: check if current jj is a mise shim
  local jj_path = vim.fn.exepath("jj")
  if jj_path and jj_path:match("mise/shims") then
    local real = find_mise_jj()
    if real then
      resolved_jj_path = real
      return resolved_jj_path
    end
  end

  -- Not a shim or couldn't resolve — use as-is. `vim.fn.exepath` returns ""
  -- (truthy in Lua) when not found, so check for the empty string explicitly
  -- before falling through to the bare "jj" string.
  resolved_jj_path = (jj_path ~= nil and jj_path ~= "" and jj_path) or "jj"
  return resolved_jj_path
end

---Execute a jj command using the resolved real binary via vim.system (no shim overhead)
---@param cmd string[] Command array where cmd[1] is "jj"
---@param cwd string Working directory
---@return string[]|nil lines, number code, string[] stderr
function M.exec(cmd, cwd)
  local real_jj = M.resolve_jj()

  -- Replace "jj" with the real binary path
  local real_cmd = { real_jj }
  for i = 2, #cmd do
    table.insert(real_cmd, cmd[i])
  end

  local result = vim.system(real_cmd, { cwd = cwd, text = true }):wait()

  local stderr = result.stderr and vim.split(result.stderr, "\n", { trimempty = true }) or {}
  if result.code == 0 and result.stdout and result.stdout ~= "" then
    return vim.split(result.stdout, "\n", { trimempty = true }), result.code, stderr
  end
  return nil, result.code, stderr
end

---Clear cached path (e.g., after mise install)
function M.clear_cache()
  resolved_jj_path = nil
end

return M
