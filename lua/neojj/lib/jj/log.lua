local M = {}

---@class NeoJJLogMeta
local meta = {}

---Parse concatenated JSON objects from jj log -T 'json(self)'
---Handles the format: {...}{...}{...} with no separator
---@param text string Raw JSON output
---@return table[] Array of decoded objects
function M.parse_json_objects(text)
  local objects = {}
  local depth = 0
  local start = nil
  local in_string = false
  local escape_next = false

  for i = 1, #text do
    local c = text:sub(i, i)

    if escape_next then
      escape_next = false
    elseif c == "\\" and in_string then
      escape_next = true
    elseif c == '"' then
      in_string = not in_string
    elseif not in_string then
      if c == "{" then
        if depth == 0 then
          start = i
        end
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 and start then
          local json_str = text:sub(start, i)
          local ok, obj = pcall(vim.json.decode, json_str)
          if ok and obj then
            table.insert(objects, obj)
          end
          start = nil
        end
      end
    end
  end

  return objects
end

---Convert a JSON commit object to a ChangeLogEntry
---@param obj table Decoded JSON object from jj log -T 'json(self)'
---@return NeoJJChangeLogEntry
function M.json_to_entry(obj)
  return {
    change_id = obj.change_id or "",
    commit_id = obj.commit_id or "",
    description = (obj.description or ""):gsub("\n$", ""),
    author_name = obj.author and obj.author.name or "",
    author_email = obj.author and obj.author.email or "",
    author_date = obj.author and obj.author.timestamp or "",
    bookmarks = {},
    empty = false,
    conflict = false,
    immutable = false,
    current_working_copy = false,
    graph = nil,
  }
end

---Parse graph lines from `jj log` default output (with graph)
---Returns entries with graph characters and basic info parsed from the display format
---@param lines string[]
---@return NeoJJChangeLogEntry[]
function M.parse_graph(lines)
  local entries = {}
  local current = nil

  for _, line in ipairs(lines) do
    -- Match commit line: graph_chars change_id email date time commit_id
    -- Examples:
    --   @  muvqvxnn nick@email 2026-03-07 02:38 7809cff3
    --   ○  tvonrrpo nick@email 2026-03-07 02:38 main 63990385
    --   ◆  zzzzzzzz root() 00000000
    local graph, rest = line:match("^([@○◆│╭╮├┤┬┴─┼%s|/\\*%.]+)(%S.*)$")
    if graph and rest then
      local change_id, remainder = rest:match("^(%S+)%s+(.+)$")
      if change_id and change_id:match("^%a+$") then
        current = {
          change_id = change_id,
          commit_id = "",
          description = "",
          author_name = "",
          author_email = "",
          author_date = "",
          bookmarks = {},
          empty = false,
          conflict = false,
          immutable = graph:match("◆") ~= nil,
          current_working_copy = graph:match("@") ~= nil,
          graph = graph,
        }

        -- Last part is usually the commit ID (hex string)
        local parts = {}
        for part in remainder:gmatch("%S+") do
          table.insert(parts, part)
        end
        if #parts >= 1 then
          local last = parts[#parts]
          if last:match("^%x+$") then
            current.commit_id = last
          end
        end

        table.insert(entries, current)
      end
    elseif current then
      -- Description line (indented under the commit)
      local desc = line:match("^[│|%s]+(.+)$")
      if desc and #desc > 0 and not desc:match("^[│|/\\%s]*$") then
        if current.description == "" then
          current.description = desc
        end
      end
    end
  end

  return entries
end

---Fetch recent changes via JSON template
---@param revset? string Revset expression (default: ancestors(@, 20))
---@param limit? number Max entries
---@return NeoJJChangeLogEntry[]
function M.list(revset, limit)
  local jj = require("neojj.lib.jj")
  limit = limit or 20
  revset = revset or ("ancestors(@, " .. limit .. ")")

  local result = jj.cli.log.no_graph
    .template("json(self)")
    .revisions(revset)
    .call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  local text = table.concat(result.stdout, "")
  local objects = M.parse_json_objects(text)

  local entries = {}
  for _, obj in ipairs(objects) do
    table.insert(entries, M.json_to_entry(obj))
  end

  return entries
end

---Update repository state with recent changes
---@param state NeoJJRepoState
function meta.update(state)
  local entries = M.list(nil, 20)
  state.recent.items = entries

  -- Enrich head description from log if status didn't provide it
  if #entries > 0 and state.head.change_id ~= "" then
    for _, entry in ipairs(entries) do
      if entry.change_id == state.head.change_id
        or state.head.change_id:find(entry.change_id, 1, true) == 1
        or entry.change_id:find(state.head.change_id, 1, true) == 1 then
        if entry.description ~= "" and (state.head.description == "" or state.head.description:match("^%(")) then
          state.head.description = entry.description
        end
        break
      end
    end
  end
end

M.meta = meta

return M
