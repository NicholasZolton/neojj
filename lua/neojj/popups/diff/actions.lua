local M = {}
local config = require("neojj.config")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local jj = require("neojj.lib.jj")
local picker_cache = require("neojj.lib.picker_cache")

local function error_msg(result)
  local err = result and result.stderr or {}
  return type(err) == "table" and table.concat(err, "\n") or tostring(err)
end

local function get_diff_integration()
  local viewer = config.get_diff_viewer()
  if viewer == "codediff" then
    return require("neojj.integrations.codediff")
  else
    return require("neojj.integrations.diffview")
  end
end

--- Resolve a jj change ID to a git commit hash
local function resolve_to_git_hash(change_id)
  local result = jj.cli.log
    .args("-r", change_id, "--no-graph", "-T", "commit_id")
    .call()
  if result and result.code == 0 and result.stdout then
    local hash = type(result.stdout) == "table"
      and result.stdout[1]
      or result.stdout
    if hash then return vim.trim(hash) end
  end
  return nil
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
    get_diff_integration().open("commit", item.name)
  end
end

function M.range(popup)
  local options = picker_cache.get_all_revisions()

  local from_sel = FuzzyFinderBuffer.new(options):open_async {
    prompt_prefix = "Diff from",
    refocus_status = false,
  }
  if not from_sel then return end
  local from_change = from_sel:match("^(%S+)")
  local from_hash = resolve_to_git_hash(from_change)
  if not from_hash then return end

  local to_sel = FuzzyFinderBuffer.new(options):open_async {
    prompt_prefix = "Diff to",
    refocus_status = false,
  }
  if not to_sel then return end
  local to_change = to_sel:match("^(%S+)")
  local to_hash = resolve_to_git_hash(to_change)
  if not to_hash then return end

  popup:close()
  get_diff_integration().open("range", from_hash .. ".." .. to_hash)
end

function M.working_copy(popup)
  popup:close()
  get_diff_integration().open("worktree")
end

function M.change(popup)
  local options = picker_cache.get_all_revisions()

  local selected = FuzzyFinderBuffer.new(options):open_async { refocus_status = false }
  if not selected then return end
  local change_id = selected:match("^(%S+)")
  if not change_id then return end
  local git_hash = resolve_to_git_hash(change_id)
  if not git_hash then return end

  popup:close()
  get_diff_integration().open("commit", git_hash)
end

function M.diffedit(_popup)
  local options = picker_cache.get_all_revisions()

  local selection = FuzzyFinderBuffer.new(options):open_async { prompt_prefix = "Diffedit revision" }
  if not selection then return end
  local change_id = selection:match("^(%S+)")
  if not change_id then return end

  local notification = require("neojj.lib.notification")
  local result = jj.cli.diffedit.revision(change_id).call { pty = true }
  if result and result.code == 0 then
    notification.info("Diffedit complete", { dismiss = true })
  else
    notification.warn("Diffedit failed: " .. error_msg(result), { dismiss = true })
  end
end

return M
