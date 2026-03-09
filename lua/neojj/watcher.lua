-- Adapted from https://github.com/lewis6991/gitsigns.nvim/blob/main/lua/gitsigns/watcher.lua#L103

local logger = require("neojj.logger")
local util = require("neojj.lib.util")
local jj = require("neojj.lib.jj")
local config = require("neojj.config")
local a = require("plenary.async")

---@class Watcher
---@field jj_dir string
---@field buffers table<StatusBuffer>
---@field running boolean
---@field fs_event_handler uv_fs_event_t
---@field poll_timer uv_timer_t|nil
---@field last_op_id string|nil
local Watcher = {}
Watcher.__index = Watcher

---@param root string
---@return Watcher
function Watcher.new(root)
  local instance = {
    buffers = {},
    jj_dir = root .. "/.jj",
    running = false,
    fs_event_handler = assert(vim.uv.new_fs_event()),
    poll_timer = nil,
    last_op_id = nil,
  }

  setmetatable(instance, Watcher)

  return instance
end

local instances = {}

---@param root string?
---@return Watcher
function Watcher.instance(root)
  local dir = root or vim.uv.cwd()
  assert(dir, "Root must exist")

  dir = vim.fs.normalize(dir)

  if not instances[dir] then
    instances[dir] = Watcher.new(dir)
  end

  return instances[dir]
end

---@param buffer StatusBuffer
---@return Watcher
function Watcher:register(buffer)
  logger.debug("[WATCHER] Registered buffer " .. buffer:id())

  self.buffers[buffer:id()] = buffer
  return self:start()
end

---@return Watcher
function Watcher:unregister(buffer)
  if not self.buffers[buffer:id()] then
    return self
  end
  self.buffers[buffer:id()] = nil

  logger.debug("[WATCHER] Unregistered buffer " .. buffer:id())

  if vim.tbl_isempty(self.buffers) and self.running then
    logger.debug("[WATCHER] No registered buffers - stopping")
    self:stop()
  end

  return self
end

---@return Watcher
function Watcher:start()
  if not config.values.filewatcher.enabled then
    return self
  end

  if self.running then
    return self
  end

  logger.debug("[WATCHER] Watching jj dir: " .. self.jj_dir)
  self.running = true
  self.fs_event_handler:start(self.jj_dir, {}, self:fs_event_callback())
  self:start_poll()
  return self
end

---@return Watcher
function Watcher:stop()
  if not config.values.filewatcher.enabled then
    return self
  end

  if not self.running then
    return self
  end

  logger.debug("[WATCHER] Stopped watching jj dir: " .. self.jj_dir)
  self.running = false
  self.fs_event_handler:stop()
  self:stop_poll()
  return self
end

function Watcher:start_poll()
  local interval = config.values.filewatcher.poll_interval or 0
  if interval <= 0 then
    return
  end

  if self.poll_timer then
    return
  end

  -- Capture initial op id
  self.last_op_id = self:get_current_op_id()

  self.poll_timer = vim.uv.new_timer()
  self.poll_timer:start(interval, interval, vim.schedule_wrap(function()
    if vim.tbl_isempty(self.buffers) then
      return
    end

    local current_op = self:get_current_op_id()
    if current_op and current_op ~= self.last_op_id then
      logger.debug("[WATCHER] Poll detected op change: " .. (self.last_op_id or "nil") .. " -> " .. current_op)
      self.last_op_id = current_op
      self:dispatch_refresh()
    end
  end))

  logger.debug("[WATCHER] Started polling every " .. interval .. "ms")
end

function Watcher:stop_poll()
  if self.poll_timer then
    self.poll_timer:stop()
    self.poll_timer:close()
    self.poll_timer = nil
    logger.debug("[WATCHER] Stopped polling")
  end
end

function Watcher:get_current_op_id()
  local root = self.jj_dir:gsub("/.jj$", "")
  local lines, code = require("neojj.lib.jj.shell").exec(
    { "jj", "--no-pager", "--color=never", "--ignore-working-copy", "op", "log", "--no-graph", "-T", "self.id()", "-n", "1" },
    root
  )
  if code == 0 and lines and lines[1] then
    return lines[1]
  end
  return nil
end

local WATCH_IGNORE = {
  -- jj internal files that change frequently but don't affect UI state
  ["working_copy"] = true,
}

function Watcher:fs_event_callback()
  local refresh_debounced = util.debounce_trailing(
    200,
    a.void(util.throttle_by_id(function(info)
      logger.debug(info)
      self:dispatch_refresh()
    end, true))
  )

  return function(err, filename, events)
    if err then
      logger.error(string.format("[WATCHER] JJ dir update error: %s", err))
      return
    end

    local info = string.format(
      "[WATCHER] JJ dir update: '%s' %s",
      filename,
      vim.inspect(events, { indent = "", newline = " " })
    )

    -- stylua: ignore
    if
      filename == nil or
      WATCH_IGNORE[filename] or
      vim.endswith(filename, ".lock") or
      vim.endswith(filename, "~") or
      filename:match("%d%d%d%d")
    then
      return
    end

    refresh_debounced(info)
  end
end

function Watcher:dispatch_refresh()
  jj.repo:dispatch_refresh {
    source = "watcher",
    callback = function()
      for name, buffer in pairs(self.buffers) do
        logger.debug("[WATCHER] Dispatching redraw to " .. name)
        buffer:redraw()
      end
    end,
  }
end

return Watcher
