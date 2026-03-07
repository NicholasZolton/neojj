local M = {}
local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local LogViewBuffer = require("neojj.buffers.log_view")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")

local function get_changes(popup, revset)
  local jj_log = require("neojj.lib.jj.log")
  local limit = 256

  -- Get limit from popup args
  for i, arg in ipairs(popup:get_arguments()) do
    if arg == "-n" and popup:get_arguments()[i + 1] then
      limit = tonumber(popup:get_arguments()[i + 1]) or 256
    end
  end

  return jj_log.list(revset, limit)
end

local function open_log(popup, changes, header)
  LogViewBuffer.new(
    changes,
    popup:get_internal_arguments(),
    popup.state.env.files,
    function(_offset) return {} end,
    header,
    {}
  ):open()
end

function M.log_all(popup)
  local changes = get_changes(popup, nil)
  open_log(popup, changes, "All changes")
end

function M.log_revset(popup)
  local revset = input.get_user_input("Revset")
  if not revset or revset == "" then return end

  local changes = get_changes(popup, revset)
  open_log(popup, changes, "Changes matching: " .. revset)
end

function M.log_bookmark(popup)
  local bookmarks = {}
  for _, item in ipairs(jj.repo.state.bookmarks.items) do
    if not item.remote then
      table.insert(bookmarks, item.name)
    end
  end

  local bm = FuzzyFinderBuffer.new(bookmarks):open_async { prompt_prefix = "Log bookmark" }
  if not bm then return end

  local changes = get_changes(popup, bm .. "::@")
  open_log(popup, changes, "Changes in " .. bm)
end

function M.op_log(_popup)
  require("neojj.buffers.op_view").new():open()
end

function M.limit_to_files()
  local a = require("plenary.async")
  local fn = function(popup, option)
    if option.value ~= "" then
      popup.state.env.files = nil
      return ""
    end

    local result = jj.cli.file_list.call { hidden = true, trim = true }
    local files = {}
    if result and result.code == 0 then
      files = result.stdout
    end

    local eventignore = vim.o.eventignore
    vim.o.eventignore = "WinLeave"
    local selected = FuzzyFinderBuffer.new(files):open_async {
      allow_multi = true,
      refocus_status = false,
    }
    vim.o.eventignore = eventignore

    if not selected or vim.tbl_isempty(selected) then
      popup.state.env.files = nil
      return ""
    end

    popup.state.env.files = selected
    local formatted = {}
    for _, file in ipairs(selected) do
      table.insert(formatted, string.format([[ "%s"]], file))
    end
    return table.concat(formatted, "")
  end

  return a.wrap(fn, 2)
end

return M
