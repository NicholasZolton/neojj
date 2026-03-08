local M = {}

local did_setup = false

---Setup neojj
---@param opts NeoJJConfig
function M.setup(opts)
  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.notify("NeoJJ HEAD requires at least NVIM 0.10 - Pin to tag 'v0.0.1' for NVIM 0.9.x")
    return
  end

  local config = require("neojj.config")
  local signs = require("neojj.lib.signs")
  local autocmds = require("neojj.autocmds")
  local hl = require("neojj.lib.hl")
  local state = require("neojj.lib.state")
  local logger = require("neojj.logger")

  if did_setup then
    logger.debug("Already did setup!")
    return
  end
  did_setup = true

  M.autocmd_group = vim.api.nvim_create_augroup("NeoJJ", { clear = false })

  M.status = require("neojj.buffers.status")

  M.dispatch_reset = function()
    local instance = M.status.instance()
    if instance then
      instance:dispatch_reset()
    end
  end

  M.refresh = function()
    local instance = M.status.instance()
    if instance then
      instance:refresh()
    end
  end

  M.reset = function()
    local instance = M.status.instance()
    if instance then
      instance:reset()
    end
  end

  M.dispatch_refresh = function()
    local instance = M.status.instance()
    if instance then
      instance:dispatch_refresh()
    end
  end

  M.close = function()
    local instance = M.status.instance()
    if instance then
      instance:close()
    end
  end

  M.lib = require("neojj.lib")
  M.cli = require("neojj.lib.jj.cli")
  M.popups = require("neojj.popups")
  M.config = config
  M.notification = require("neojj.lib.notification")

  config.setup(opts)
  hl.setup(config.values)
  signs.setup(config.values)
  state.setup(config.values)
  autocmds.setup()
end

local function construct_opts(opts)
  opts = opts or {}

  if opts.cwd and not opts.no_expand then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  if not opts.cwd then
    local jj_cli = require("neojj.lib.jj.cli")
    local root = jj_cli.find_workspace_root(".")
    opts.cwd = root or vim.uv.cwd()
    opts._workspace_root = root
  end

  return opts
end

local function open_popup(name)
  local has_pop, popup = pcall(require, "neojj.popups." .. name)
  if not has_pop then
    M.notification.error(("Invalid popup %q"):format(name))
  else
    popup.create {}
  end
end

local function open_status_buffer(opts)
  local status = require("neojj.buffers.status")
  local config = require("neojj.config")

  local root = opts._workspace_root or opts.cwd
  local repo = require("neojj.lib.jj.repository").instance(opts.cwd)
  status.new(config.values, repo.worktree_root or root, opts.cwd):open(opts.kind):dispatch_refresh()
end

---@alias Popup
---| "bookmark"
---| "change"
---| "commit"
---| "diff"
---| "fetch"
---| "help"
---| "log"
---| "margin"
---| "push"
---| "rebase"
---| "remote"
---| "resolve"
---| "split"
---| "squash"
---| "yank"

---@class OpenOpts
---@field cwd string|nil
---@field [1] Popup|nil
---@field kind string|nil
---@field no_expand boolean|nil

---@param opts OpenOpts|nil
function M.open(opts)
  if not did_setup then
    M.setup {}
  end

  opts = construct_opts(opts)

  if not opts._workspace_root then
    M.notification.error("The current working directory is not a jj workspace")
    return
  end

  if opts[1] ~= nil then
    local a = require("plenary.async")
    local jj = require("neojj.lib.jj")
    local cb = function()
      open_popup(opts[1])
    end

    a.void(function()
      jj.repo:dispatch_refresh { source = "popup", callback = cb }
    end)()
  else
    open_status_buffer(opts)
  end
end

-- This can be used to create bindable functions for custom keybindings:
--   local neojj = require("neojj")
--   vim.keymap.set('n', '<leader>gcc', neojj.action('commit', 'commit', { '--verbose', '--all' }))
--
---@param popup  string Name of popup, as found in `lua/neojj/popups/*`
---@param action string Name of action for popup, found in `lua/neojj/popups/*/actions.lua`
---@param args   table? CLI arguments to pass to jj command
---@return function
function M.action(popup, action, args)
  local util = require("neojj.lib.util")
  local jj = require("neojj.lib.jj")
  local a = require("plenary.async")

  args = args or {}

  local internal_args = {
    graph = util.remove_item_from_table(args, "--graph"),
    color = util.remove_item_from_table(args, "--color"),
    decorate = util.remove_item_from_table(args, "--decorate"),
  }

  return function()
    a.void(function()
      local ok, actions = pcall(require, "neojj.popups." .. popup .. ".actions")
      if ok then
        local fn = actions[action]
        if fn then
          local action = function()
            fn {
              close = function() end,
              state = { env = {} },
              get_arguments = function()
                return args
              end,
              get_internal_arguments = function()
                return internal_args
              end,
            }
          end

          jj.repo:dispatch_refresh { source = "action", callback = action }
        else
          M.notification.error(
            string.format(
              "Invalid action %s for %s popup\nValid actions are: %s",
              action,
              popup,
              table.concat(vim.tbl_keys(actions), ", ")
            )
          )
        end
      else
        M.notification.error("Invalid popup: " .. popup)
      end
    end)()
  end
end

function M.complete(arglead)
  if arglead:find("^kind=") then
    return {
      "kind=replace",
      "kind=tab",
      "kind=split",
      "kind=split_above",
      "kind=split_above_all",
      "kind=split_below",
      "kind=split_below_all",
      "kind=vsplit",
      "kind=floating",
      "kind=auto",
    }
  end

  if arglead:find("^cwd=") then
    return {
      "cwd=" .. vim.uv.cwd(),
    }
  end

  return vim.tbl_filter(function(arg)
    return arg:match("^" .. arglead)
  end, {
    "kind=",
    "cwd=",
    "bookmark",
    "change",
    "commit",
    "diff",
    "fetch",
    "help",
    "log",
    "margin",
    "push",
    "rebase",
    "remote",
    "resolve",
    "split",
    "squash",
    "yank",
  })
end

function M.get_log_file_path()
  return vim.fn.stdpath("cache") .. "/neojj.log"
end

function M.get_config()
  return M.config.values
end

return M
