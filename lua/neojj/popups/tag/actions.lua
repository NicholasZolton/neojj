local M = {}

local jj = require("neojj.lib.jj")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")
local FuzzyFinderBuffer = require("neojj.buffers.fuzzy_finder")
local picker_cache = require("neojj.lib.picker_cache")
local Watcher = require("neojj.watcher")

---@param result ProcessResult|nil
---@return string
local function result_error(result)
  if not result then
    return "command did not return a result"
  end

  local stderr = result.stderr or {}
  local stdout = result.stdout or {}
  local message = table.concat(stderr, "\n")
  if message == "" then
    message = table.concat(stdout, "\n")
  end
  return message ~= "" and message or "command failed without output"
end

---@param target string
---@return boolean
local function is_root(target)
  return target == "root" or target == "root()" or target:match("^z+$") ~= nil
end

---@param target string
---@return boolean
local function is_working_copy(target)
  if target == "@" then
    return true
  end

  local state = jj.repo and jj.repo.state
  local head = state and state.head and state.head.change_id or ""
  return target ~= "" and head ~= "" and head:sub(1, #target) == target
end

---@param target string
---@return boolean
local function confirm_working_copy(target)
  if not is_working_copy(target) then
    return true
  end
  return input.get_permission(
    "Tagging the working-copy commit makes it immutable; Jujutsu creates a new working-copy child. Continue?"
  )
end

---@param entries (string|{ text: string })[]
---@param selection string|{ text: string }
---@return boolean
local function is_listed_selection(entries, selection)
  local selected_text = type(selection) == "table" and selection.text or selection
  for _, entry in ipairs(entries) do
    local entry_text = type(entry) == "table" and entry.text or entry
    if selected_text == entry_text then
      return true
    end
  end
  return false
end

---@param result ProcessResult|nil
---@param success string
---@param failure string
local function report_and_refresh(result, success, failure)
  if result and result.code == 0 then
    notification.info(success, { dismiss = true })
    Watcher.instance(jj.repo.worktree_root):dispatch_refresh()
  else
    notification.warn(failure .. ": " .. result_error(result), { dismiss = true })
  end
end

---@param popup PopupData|nil
---@return string
local function popup_revision(popup)
  return (popup and popup:get_env("revision")) or "@"
end

function M.create(popup)
  local name = input.get_user_input("Tag name")
  if not name or vim.trim(name) == "" then
    return
  end

  local target = popup_revision(popup)
  if is_root(target) then
    notification.warn("Cannot tag root revision", { dismiss = true })
    return
  end
  if not confirm_working_copy(target) then
    return
  end

  local result = require("neojj.lib.jj.tag").create(name, target)
  report_and_refresh(result, "Created tag " .. name .. " at " .. target, "Failed to create tag")
end

function M.move(_popup)
  local names = picker_cache.get_local_tag_names()
  local name = FuzzyFinderBuffer.new(names):open_async { prompt_prefix = "Move tag", refocus_status = false }
  if not name then
    return
  end
  if not vim.tbl_contains(names, name) then
    notification.warn("Move aborted: select a local tag", { dismiss = true })
    return
  end

  local revisions = picker_cache.get_all_revisions()
  local selection = FuzzyFinderBuffer.new(revisions)
    :open_async { prompt_prefix = "Move '" .. name .. "' to revision", refocus_status = false }
  if not selection then
    return
  end
  if not is_listed_selection(revisions, selection) then
    notification.warn("Move aborted: select a listed revision", { dismiss = true })
    return
  end
  local target = picker_cache.parse_selection(selection)
  if not target then
    return
  end
  if is_root(target) then
    notification.warn("Cannot tag root revision", { dismiss = true })
    return
  end

  if not confirm_working_copy(target) then
    return
  end

  local old_target = "unknown"
  for _, item in ipairs(picker_cache.get_local_tags()) do
    if item.name == name then
      old_target = item.change_id ~= "" and item.change_id or old_target
      break
    end
  end
  if not input.get_permission(("Move tag %s from %s to %s?"):format(name, old_target, target)) then
    return
  end

  local result = require("neojj.lib.jj.tag").move(name, target)
  report_and_refresh(result, "Moved tag " .. name .. " to " .. target, "Failed to move tag")
end

function M.delete(_popup)
  local names = picker_cache.get_local_tag_names()
  local name = FuzzyFinderBuffer.new(names)
    :open_async { prompt_prefix = "Delete local tag", refocus_status = false }
  if not name then
    return
  end
  if not vim.tbl_contains(names, name) then
    notification.warn("Delete aborted: select a local tag", { dismiss = true })
    return
  end

  local target = "unknown"
  for _, item in ipairs(picker_cache.get_local_tags()) do
    if item.name == name then
      target = item.change_id ~= "" and item.change_id or target
      break
    end
  end
  if not input.get_permission(("Delete local tag %s at %s?"):format(name, target)) then
    return
  end

  local result = require("neojj.lib.jj.tag").delete(name)
  report_and_refresh(result, "Deleted local tag " .. name, "Failed to delete local tag")
end

return M
