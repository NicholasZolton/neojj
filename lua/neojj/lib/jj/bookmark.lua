---@class NeojjBookmark
---@field parse_list fun(lines: string[]): NeojjBookmarkItem[]
---@field list fun(): NeojjBookmarkItem[]
---@field create fun(name: string, revision?: string): ProcessResult?
---@field move fun(name: string, to: string, allow_backwards?: boolean): ProcessResult?
---@field delete fun(name: string): ProcessResult?
---@field track fun(bookmark_at_remote: string): ProcessResult?
---@field forget fun(name: string): ProcessResult?
---@field rename fun(old_name: string, new_name: string): ProcessResult?
---@field set fun(name: string, revision: string, allow_backwards?: boolean): ProcessResult?
---@field untrack fun(bookmark_at_remote: string): ProcessResult?
---@field advance fun(to: string): ProcessResult?
---@field parse_template_list fun(lines: string[]): NeojjBookmarkItem[]
local M = {}

---@class NeojjBookmarkMeta
local meta = {}

---Strip jj display decorations from a bookmark name: the unpushed marker
---(`name*`), conflict markers (`name??`), and a remote qualifier
---(`name@origin`). Git ref names cannot contain `*`, `?`, or `@`-qualifiers,
---so the leading run of other characters is the bare name.
---@param name string|nil
---@return string|nil
function M.normalize(name)
  if type(name) ~= "string" then
    return nil
  end

  local bare = name:match("^([^@*?]+)")
  return bare
end

---Parse `jj bookmark list --all` output
---Local format: "name: change_id commit_id [| ] description"
---Local deleted: "name (deleted)"
---Local tracking: "  @remote: change_id commit_id description"
---Remote format: "name@remote: change_id commit_id description"
---@param lines string[]
---@return NeojjBookmarkItem[]
function M.parse_list(lines)
  local items = {}
  local current_name = nil

  for _, line in ipairs(lines) do
    if line:match("^%s+@") then
      -- Remote tracking line (indented): "  @remote: change_id commit_id desc"
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
    elseif not line:match("^Hint:") then
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
---@return NeojjBookmarkItem[]
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
  local name, remote = bookmark_at_remote:match("^(.+)@(.+)$")
  if name and remote then
    return jj.cli.bookmark_track.args(name).remote(remote).call()
  end
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
---Format: name\tremote\tchange_id\tcommit_id\ttimestamp\tdescription\tpresent\tconflict\tshortest_prefix
---@param lines string[]
---@return NeojjBookmarkItem[]
function M.parse_template_list(lines)
  local items = {}
  for _, line in ipairs(lines) do
    if line ~= "" and not line:match("^Hint:") then
      local parts = vim.split(line, "\t", { plain = true })
      if #parts >= 8 then
        local name = parts[1]
        local remote = parts[2] ~= "" and parts[2] or nil
        local change_id = parts[3]
        local commit_id = parts[4]
        local timestamp = parts[5]
        local description = parts[6]
        local present = parts[7] == "1"
        local conflict = parts[8] == "1"
        local shortest_prefix = parts[9] ~= "" and parts[9] or nil
        local deleted = not present

        if conflict then
          description = "(conflicted)"
        elseif deleted then
          description = "(deleted)"
        end

        table.insert(items, {
          name = name,
          change_id = change_id,
          commit_id = commit_id,
          description = description,
          remote = remote,
          timestamp = timestamp,
          deleted = deleted,
          conflict = conflict,
          shortest_prefix = shortest_prefix,
        })
      end
    end
  end
  return items
end

-- Template for structured bookmark output with timestamps
local BOOKMARK_TEMPLATE =
  'self.name() ++ "\\t" ++ if(self.remote(), self.remote(), "") ++ "\\t" ++ if(self.normal_target(), self.normal_target().change_id() ++ "\\t" ++ self.normal_target().commit_id() ++ "\\t" ++ self.normal_target().committer().timestamp() ++ "\\t" ++ self.normal_target().description().first_line(), "\\t\\t\\t") ++ "\\t" ++ if(self.present(), "1", "0") ++ "\\t" ++ if(self.conflict(), "1", "0") ++ "\\t" ++ if(self.normal_target(), self.normal_target().change_id().shortest(8).prefix(), "") ++ "\\n"'

---Update repository state with bookmark data
---@param state NeojjRepoState
function meta.update(state)
  local config = require("neojj.config")
  local section_config = config.values.sections and config.values.sections.bookmarks or {}
  local show_deleted = section_config.show_deleted ~= false
  local show_remote = section_config.show_remote ~= false

  local shell = require("neojj.lib.jj.shell")
  local lines, code = shell.exec({
    "jj",
    "--no-pager",
    "--color=never",
    "--ignore-working-copy",
    "bookmark",
    "list",
    "--all",
    "-T",
    BOOKMARK_TEMPLATE,
  }, state.worktree_root)

  if code == 0 and lines then
    local items = M.parse_template_list(lines)

    -- Filter based on config
    local filtered = {}
    for _, item in ipairs(items) do
      local is_remote = item.remote and item.remote ~= ""
      local skip = item.remote == "git"
        or (item.deleted and not show_deleted)
        or (is_remote and not show_remote)
      if not skip then
        table.insert(filtered, item)
      end
    end

    -- Mark local bookmarks that are ahead of their remote tracking ref
    local remote_commits = {}
    for _, item in ipairs(filtered) do
      if item.remote and item.remote ~= "" and item.commit_id ~= "" then
        remote_commits[item.name] = remote_commits[item.name] or {}
        remote_commits[item.name][item.remote] = item.commit_id
      end
    end
    for _, item in ipairs(filtered) do
      if not item.remote or item.remote == "" then
        local remotes = remote_commits[item.name]
        if remotes then
          for _, remote_commit in pairs(remotes) do
            if remote_commit ~= item.commit_id then
              item.unpushed = true
              break
            end
          end
        end
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
