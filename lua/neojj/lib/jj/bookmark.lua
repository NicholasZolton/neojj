local M = {}

---@class NeoJJBookmarkMeta
local meta = {}

---Parse `jj bookmark list` output
---Format: "name: change_id commit_id [| ] description"
---Remote: "  @remote: change_id commit_id description"
---@param lines string[]
---@return NeoJJBookmarkItem[]
function M.parse_list(lines)
  local items = {}
  local current_name = nil

  for _, line in ipairs(lines) do
    -- Remote tracking bookmark: "  @remote: change_id commit_id desc"
    local remote, rchange, rcommit, rdesc = line:match("^%s+@(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
    if remote and current_name then
      table.insert(items, {
        name = current_name,
        change_id = rchange,
        commit_id = rcommit,
        description = (rdesc or ""):gsub("^|%s*", ""),
        remote = remote,
      })
    else
      -- Local bookmark: "name: change_id commit_id [| ] desc"
      local name, change_id, commit_id, rest = line:match("^(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
      if name then
        current_name = name
        local desc = (rest or ""):gsub("^|%s*", "")
        table.insert(items, {
          name = name,
          change_id = change_id,
          commit_id = commit_id,
          description = desc,
          remote = nil,
        })
      end
    end
  end

  return items
end

---List bookmarks
---@return NeoJJBookmarkItem[]
function M.list()
  local jj = require("neojj.lib.jj")
  local result = jj.cli.bookmark_list.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return M.parse_list(result.stdout)
  end
  return {}
end

---Create a bookmark
---@param name string
---@param revision? string
function M.create(name, revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_create.args(name)
  if revision then
    builder = builder.revision(revision)
  end
  return builder.call()
end

---Move a bookmark
---@param name string
---@param to string Target revision
---@param allow_backwards? boolean
function M.move(name, to, allow_backwards)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_move.args(name).to(to)
  if allow_backwards then
    builder = builder.allow_backwards
  end
  return builder.call()
end

---Delete a bookmark
---@param name string
function M.delete(name)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_delete.args(name).call()
end

---Track a remote bookmark
---@param bookmark_at_remote string e.g., "main@origin"
function M.track(bookmark_at_remote)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_track.args(bookmark_at_remote).call()
end

---Forget a bookmark
---@param name string
function M.forget(name)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_forget.args(name).call()
end

---Update repository state with bookmark data
---@param state NeoJJRepoState
function meta.update(state)
  local shell = require("neojj.lib.jj.shell")
  local lines, code = shell.exec(
    { "jj", "--no-pager", "--color=never", "--ignore-working-copy", "bookmark", "list" },
    state.worktree_root
  )

  if code == 0 and lines then
    state.bookmarks.items = M.parse_list(lines)
  else
    state.bookmarks.items = {}
  end
end

M.meta = meta

return M
