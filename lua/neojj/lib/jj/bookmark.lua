local M = {}

---@class NeoJJBookmarkMeta
local meta = {}

---Parse `jj bookmark list --all` output
---Local format: "name: change_id commit_id [| ] description"
---Local deleted: "name (deleted)"
---Local tracking: "  @remote: change_id commit_id description"
---Remote format: "name@remote: change_id commit_id description"
---@param lines string[]
---@return NeoJJBookmarkItem[]
function M.parse_list(lines)
  local items = {}
  local current_name = nil

  for _, line in ipairs(lines) do
    -- Skip hint lines
    if line:match("^Hint:") then
      -- skip
    -- Remote tracking line (indented): "  @remote: change_id commit_id desc"
    elseif line:match("^%s+@") then
      local remote, rchange, rcommit, rdesc = line:match("^%s+@(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
      if remote and current_name then
        table.insert(items, {
          name = current_name,
          change_id = rchange,
          commit_id = rcommit,
          description = (rdesc or ""):gsub("^|%s*", ""),
          remote = remote,
        })
      end
    else
      -- Remote bookmark: "name@remote: change_id commit_id desc"
      local rname, remote, change_id, commit_id, rest = line:match("^(.-)@(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
      if rname and remote then
        current_name = nil
        local desc = (rest or ""):gsub("^|%s*", "")
        table.insert(items, {
          name = rname,
          change_id = change_id,
          commit_id = commit_id,
          description = desc,
          remote = remote,
        })
      else
        -- Local bookmark: "name: change_id commit_id [| ] desc"
        local name, lchange, lcommit, lrest = line:match("^(%S+):%s+(%S+)%s+(%S+)%s*(.*)")
        if name then
          current_name = name
          local desc = (lrest or ""):gsub("^|%s*", "")
          table.insert(items, {
            name = name,
            change_id = lchange,
            commit_id = lcommit,
            description = desc,
            remote = nil,
          })
        else
          -- Deleted bookmark: "name (deleted)" — skip these
          local dname = line:match("^(%S+)%s+%(deleted%)")
          if dname then
            current_name = dname
          end
        end
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

---Rename a bookmark
---@param old_name string
---@param new_name string
function M.rename(old_name, new_name)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_rename.args(old_name, new_name).call()
end

---Set (create or update) a bookmark
---@param name string
---@param revision? string
---@param allow_backwards? boolean
function M.set(name, revision, allow_backwards)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_set.args(name)
  if revision then
    builder = builder.revision(revision)
  end
  if allow_backwards then
    builder = builder.allow_backwards
  end
  return builder.call()
end

---Untrack a remote bookmark
---@param bookmark_at_remote string e.g., "main@origin"
function M.untrack(bookmark_at_remote)
  local jj = require("neojj.lib.jj")
  return jj.cli.bookmark_untrack.args(bookmark_at_remote).call()
end

---Advance closest bookmarks to a target revision
---@param to? string Target revision (defaults to @)
function M.advance(to)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.bookmark_advance
  if to then
    builder = builder.to(to)
  end
  return builder.call()
end

---Parse structured bookmark template output (tab-separated)
---Format: name\tremote\tchange_id\tcommit_id\ttimestamp\tdescription
---@param lines string[]
---@return NeoJJBookmarkItem[]
function M.parse_template_list(lines)
  local items = {}
  for _, line in ipairs(lines) do
    if line == "" or line:match("^Hint:") then
      goto continue
    end
    local parts = vim.split(line, "\t", { plain = true })
    if #parts >= 6 then
      local name = parts[1]
      local remote = parts[2] ~= "" and parts[2] or nil
      local change_id = parts[3]
      local commit_id = parts[4]
      local timestamp = parts[5]
      local description = parts[6]
      local deleted = change_id == "" and commit_id == ""
      table.insert(items, {
        name = name,
        change_id = change_id,
        commit_id = commit_id,
        description = deleted and "(deleted)" or description,
        remote = remote,
        timestamp = timestamp,
        deleted = deleted,
      })
    end
    ::continue::
  end
  return items
end

-- Template for structured bookmark output with timestamps
local BOOKMARK_TEMPLATE = 'self.name() ++ "\\t" ++ if(self.remote(), self.remote(), "") ++ "\\t" ++ if(self.normal_target(), self.normal_target().change_id() ++ "\\t" ++ self.normal_target().commit_id() ++ "\\t" ++ self.normal_target().committer().timestamp() ++ "\\t" ++ self.normal_target().description().first_line(), "\\t\\t\\t\\t(deleted)") ++ "\\n"'

---Update repository state with bookmark data
---@param state NeoJJRepoState
function meta.update(state)
  local config = require("neojj.config")
  local section_config = config.values.sections and config.values.sections.bookmarks or {}
  local show_deleted = section_config.show_deleted ~= false
  local show_remote = section_config.show_remote ~= false

  local shell = require("neojj.lib.jj.shell")
  local lines, code = shell.exec(
    { "jj", "--no-pager", "--color=never", "--ignore-working-copy", "bookmark", "list", "--all", "-T", BOOKMARK_TEMPLATE },
    state.worktree_root
  )

  if code == 0 and lines then
    local items = M.parse_template_list(lines)

    -- Filter based on config
    local filtered = {}
    for _, item in ipairs(items) do
      local is_remote = item.remote and item.remote ~= ""
      if item.remote == "git" then
        -- skip @git bookmarks (jj internal tracking refs)
      elseif item.deleted and not show_deleted then
        -- skip
      elseif is_remote and not show_remote then
        -- skip
      else
        table.insert(filtered, item)
      end
    end

    -- Sort: local bookmarks first (by timestamp desc), then remote (by timestamp desc)
    table.sort(filtered, function(a, b)
      local a_remote = a.remote and a.remote ~= ""
      local b_remote = b.remote and b.remote ~= ""
      if a_remote ~= b_remote then
        return not a_remote -- local first
      end
      -- Sort by timestamp descending (newest first), fall back to name
      if a.timestamp ~= b.timestamp then
        return (a.timestamp or "") > (b.timestamp or "")
      end
      return a.name < b.name
    end)
    state.bookmarks.items = filtered
  else
    state.bookmarks.items = {}
  end
end

M.meta = meta

return M
