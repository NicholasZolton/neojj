local M = {}
local config = require("neojj.config")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local jj = require("neojj.lib.jj")

local function get_diff_integration()
  local viewer = config.get_diff_viewer()
  if viewer == "codediff" then
    return require("neojj.integrations.codediff")
  else
    return require("neojj.integrations.diffview")
  end
end

function M.this(popup)
  popup:close()
  local item = popup:get_env("item")
  local section = popup:get_env("section")

  if section and section.name and item and item.name then
    get_diff_integration().open(section.name, item.name, { only = true })
  elseif section and section.name then
    get_diff_integration().open(section.name, nil, { only = true })
  elseif item and item.name then
    get_diff_integration().open("range", item.name)
  end
end

function M.range(popup)
  local options = {}
  for _, item in ipairs(jj.repo.state.recent.items) do
    local short = string.sub(item.change_id, 1, 12)
    local desc = item.description ~= "" and item.description or "(no description)"
    table.insert(options, short .. " " .. desc)
  end

  local from_sel = FuzzyFinderBuffer.new(options):open_async {
    prompt_prefix = "Diff from",
    refocus_status = false,
  }
  if not from_sel then return end
  local range_from = from_sel:match("^(%S+)")

  local to_sel = FuzzyFinderBuffer.new(options):open_async {
    prompt_prefix = "Diff to",
    refocus_status = false,
  }
  if not to_sel then return end
  local range_to = to_sel:match("^(%S+)")

  popup:close()
  get_diff_integration().open("range", range_from .. ".." .. range_to)
end

function M.working_copy(popup)
  popup:close()
  get_diff_integration().open("worktree")
end

function M.change(popup)
  popup:close()

  local options = {}
  for _, item in ipairs(jj.repo.state.recent.items) do
    local short = string.sub(item.change_id, 1, 12)
    local desc = item.description ~= "" and item.description or "(no description)"
    table.insert(options, short .. " " .. desc)
  end

  local selected = FuzzyFinderBuffer.new(options):open_async { refocus_status = false }
  if selected then
    local change_id = selected:match("^(%S+)")
    get_diff_integration().open("commit", change_id)
  end
end

return M
