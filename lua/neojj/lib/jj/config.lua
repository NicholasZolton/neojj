local M = {}

---@class JjConfigEntry
---@field value string
---@field name string
local ConfigEntry = {}
ConfigEntry.__index = ConfigEntry

---@param name string
---@param value? string
---@return JjConfigEntry
function ConfigEntry.new(name, value)
  return setmetatable({ name = name, value = value or "" }, ConfigEntry)
end

---@return string "boolean"|"number"|"string"
function ConfigEntry:type()
  if self.value == "true" or self.value == "false" then
    return "boolean"
  elseif tonumber(self.value) then
    return "number"
  else
    return "string"
  end
end

---@return boolean
function ConfigEntry:is_set()
  return self.value ~= ""
end

---@return boolean
function ConfigEntry:is_unset()
  return not self:is_set()
end

---@return boolean|number|string|nil
function ConfigEntry:read()
  if self:is_unset() then
    return nil
  end

  if self:type() == "boolean" then
    return self.value == "true"
  elseif self:type() == "number" then
    return tonumber(self.value)
  else
    return self.value
  end
end

---@param value? string
function ConfigEntry:update(value)
  if not value or value == "" then
    if self:is_set() then
      M.unset(self.name)
    end
  else
    M.set(self.name, value)
  end
end

---Get a config value
---@param key string
---@return JjConfigEntry
function M.get(key)
  local jj = require("neojj.lib.jj")
  local result = jj.cli.config_get.args(key).call { hidden = true, trim = true, ignore_error = true, await = true }
  local value = ""
  if result and result.code == 0 and result.stdout and result.stdout[1] then
    value = result.stdout[1]
  end
  return ConfigEntry.new(key, value)
end

---Set a config value (repo-scoped)
---@param key string
---@param value string
function M.set(key, value)
  if not value or value == "" then
    M.unset(key)
    return
  end
  local jj = require("neojj.lib.jj")
  jj.cli.config_set.repo.args(key, value).call { hidden = true, await = true }
end

---Unset a config value (repo-scoped)
---@param key string
function M.unset(key)
  if not M.get(key):is_set() then
    return
  end
  local jj = require("neojj.lib.jj")
  jj.cli.config_unset.repo.args(key).call { hidden = true, ignore_error = true, await = true }
end

M.ConfigEntry = ConfigEntry

return M
