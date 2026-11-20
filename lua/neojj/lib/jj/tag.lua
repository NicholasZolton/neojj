---@class NeojjTag
---@field parse_template_list fun(lines: string[]): NeojjTagItem[]
---@field list fun(): NeojjTagItem[]
---@field create fun(name: string, revision?: string): ProcessResult?
---@field move fun(name: string, revision: string): ProcessResult?
---@field delete fun(name: string): ProcessResult?
---@field meta NeojjTagMeta
local M = {}

---@class NeojjTagMeta
local meta = {}

---Parse one JSON object per tag. JSON keeps arbitrary commit-description text from shifting fields.
---@param lines string[]
---@return NeojjTagItem[]
function M.parse_template_list(lines)
  local items = {}
  for _, line in ipairs(lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if ok and type(obj) == "table" and type(obj.name) == "string" then
      local present = obj.present == true
      local conflict = obj.conflict == true
      local description = obj.description or ""
      if conflict then
        description = "(conflicted)"
      elseif not present then
        description = "(deleted)"
      end

      table.insert(items, {
        name = obj.name,
        remote = obj.remote ~= vim.NIL and obj.remote ~= "" and obj.remote or nil,
        change_id = obj.change_id or "",
        commit_id = obj.commit_id or "",
        timestamp = obj.timestamp ~= "" and obj.timestamp or nil,
        description = description,
        deleted = not present,
        conflict = conflict,
        shortest_prefix = obj.shortest_prefix ~= "" and obj.shortest_prefix or nil,
      })
    end
  end
  return items
end

---@return NeojjTagItem[]
function M.list()
  local jj = require("neojj.lib.jj")
  return jj.repo.state.tags.items
end

---@param name string
---@param revision? string
---@return ProcessResult?
function M.create(name, revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.tag_set.args(name)
  if revision then
    builder = builder.revision(revision)
  end
  return builder.call()
end

---@param name string
---@param revision string
---@return ProcessResult?
function M.move(name, revision)
  local jj = require("neojj.lib.jj")
  return jj.cli.tag_set.allow_move.revision(revision).args(name).call()
end

---@param name string
---@return ProcessResult?
function M.delete(name)
  local jj = require("neojj.lib.jj")
  return jj.cli.tag_delete.args(name).call()
end

local TAG_TEMPLATE = [=[
"{" ++
  "\"name\":" ++ json(self.name()) ++
  ",\"remote\":" ++ json(self.remote()) ++
  ",\"change_id\":" ++ if(self.normal_target(), json(self.normal_target().change_id()), "\"\"") ++
  ",\"commit_id\":" ++ if(self.normal_target(), json(self.normal_target().commit_id()), "\"\"") ++
  ",\"timestamp\":" ++ if(self.normal_target(), json(self.normal_target().committer().timestamp().utc()), "\"\"") ++
  ",\"description\":" ++ if(self.normal_target(), json(self.normal_target().description().first_line()), "\"\"") ++
  ",\"present\":" ++ json(self.present()) ++
  ",\"conflict\":" ++ json(self.conflict()) ++
  ",\"shortest_prefix\":" ++ if(self.normal_target(), json(self.normal_target().change_id().shortest(8).prefix()), "\"\"") ++
  "}\n"
]=]

---Update repository state with local tag data. Preserve last successful state on failure.
---@param state NeojjRepoState
function meta.update(state)
  local shell = require("neojj.lib.jj.shell")
  local lines, code, stderr = shell.exec({
    "jj",
    "--no-pager",
    "--color=never",
    "--ignore-working-copy",
    "tag",
    "list",
    "-T",
    TAG_TEMPLATE,
  }, state.worktree_root)

  if code ~= 0 then
    state.tags.error = table.concat(stderr or {}, "\n")
    return
  end

  local local_items = {}
  for _, item in ipairs(M.parse_template_list(lines or {})) do
    if not item.remote then
      table.insert(local_items, item)
    end
  end
  table.sort(local_items, function(a, b)
    if a.timestamp ~= b.timestamp then
      return (a.timestamp or "") > (b.timestamp or "")
    end
    return a.name < b.name
  end)

  state.tags.items = local_items
  state.tags.error = nil
end

M.meta = meta

return M
