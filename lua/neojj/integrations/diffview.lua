local M = {}

local Rev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType
local CDiffView = require("diffview.api.views.diff.diff_view").CDiffView
local dv_lib = require("diffview.lib")
local dv_utils = require("diffview.utils")

local Watcher = require("neojj.watcher")
local jj = require("neojj.lib.jj")
local a = require("plenary.async")

--- Resolve a jj change ID to a git commit hash (only if it looks like a jj ID)
local function resolve_jj_to_git(ref)
  -- jj change IDs are purely alphabetic; git hashes are hex. Skip if already hex or contains ".."
  if not ref or ref:match("%.%.") or ref:match("^[0-9a-f]+$") then
    return ref
  end

  local result = jj.cli.log
    .args("-r", ref, "--no-graph", "-T", "commit_id")
    .call()
  if result and result.code == 0 and result.stdout then
    local hash = type(result.stdout) == "table"
      and result.stdout[1]
      or result.stdout
    if hash then return vim.trim(hash) end
  end
  return ref -- fallback to original ref
end

local function get_local_diff_view(_, item_name, opts)
  local left = Rev(RevType.STAGE)
  local right = Rev(RevType.LOCAL)

  local function update_files()
    local files = {}

    -- jj has no staging area — all working copy changes are treated as staged
    local items = jj.repo.state.files.items or {}

    files.staged = {}
    for idx, item in ipairs(items) do
      local file = {
        path = item.name,
        status = item.mode and item.mode:sub(1, 1),
        stats = (item.diff and item.diff.stats) and {
          additions = item.diff.stats.additions or 0,
          deletions = item.diff.stats.deletions or 0,
        } or nil,
        left_null = vim.tbl_contains({ "A", "?" }, item.mode),
        right_null = item.mode == "D",
        selected = (item_name and item.name == item_name) or (not item_name and idx == 1),
      }

      if opts.only then
        if not item_name or (item_name and file.selected) then
          table.insert(files.staged, file)
        end
      else
        table.insert(files.staged, file)
      end
    end

    return files
  end

  local files = update_files()

  local view = CDiffView {
    git_root = jj.repo.worktree_root,
    left = left,
    right = right,
    files = files,
    update_files = update_files,
    get_file_data = function(_, path, side)
      if side == "left" then
        -- Show file contents from parent revision (@-)
        local result = jj.cli.file_show.revision("@-").args(path).call { await = true, trim = false, ignore_error = true }
        if result and result.code == 0 then
          return result.stdout
        end
        return nil
      end
      -- right side: diffview reads the working copy file directly
      return nil
    end,
  }

  view:on_files_staged(a.void(function(_)
    Watcher.instance():dispatch_refresh()
    view:update_files()
  end))

  dv_lib.add_view(view)

  return view
end

---@param section_name string
---@param item_name    string|string[]|nil
---@param opts         table|nil
function M.open(section_name, item_name, opts)
  opts = opts or {}

  -- Hack way to do an on-close callback
  if opts.on_close then
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
      buffer = opts.on_close.handle,
      once = true,
      callback = opts.on_close.fn,
    })
  end

  local view
  -- selene: allow(if_same_then_else)
  if
    (section_name == "recent" or section_name == "log" or section_name == "bookmarks" or (section_name and section_name:match("unmerged$")))
    and item_name
  then
    local range
    if type(item_name) == "table" then
      range = string.format("%s..%s", resolve_jj_to_git(item_name[1]), resolve_jj_to_git(item_name[#item_name]))
    else
      range = string.format("%s^!", resolve_jj_to_git(item_name:match("[a-f0-9]+") or item_name))
    end

    view = dv_lib.diffview_open(dv_utils.tbl_pack(range))
  elseif section_name == "range" and item_name then
    view = dv_lib.diffview_open(dv_utils.tbl_pack(resolve_jj_to_git(item_name)))
  elseif (section_name == "stashes" or section_name == "commit") and item_name then
    view = dv_lib.diffview_open(dv_utils.tbl_pack(resolve_jj_to_git(item_name) .. "^!"))
  elseif section_name == "conflict" and item_name then
    view = dv_lib.diffview_open(dv_utils.tbl_pack("--selected-file=" .. item_name))
  elseif (section_name == "conflict" or section_name == "worktree") and not item_name then
    view = dv_lib.diffview_open()
  elseif section_name ~= nil then
    -- for staged, unstaged, merge
    view = get_local_diff_view(section_name, item_name, opts)
  elseif section_name == nil and item_name ~= nil then
    view = dv_lib.diffview_open(dv_utils.tbl_pack(resolve_jj_to_git(item_name) .. "^!"))
  else
    view = dv_lib.diffview_open()
  end

  if view then
    view:open()
  end
end

return M
