local M = {}

---@class NeojjLogMeta
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
---@return NeojjChangeLogEntry
function M.json_to_entry(obj)
  return {
    change_id = obj.change_id or "",
    commit_id = obj.commit_id or "",
    description = vim.split((obj.description or ""):gsub("\n+$", ""), "\n")[1],
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
---@return NeojjChangeLogEntry[]
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

---Fetch recent changes via JSON template (no graph)
---@param revset? string Revset expression (default: ancestors(@, N))
---@param limit? number Max entries
---@return NeojjChangeLogEntry[]
-- Template that appends immutable/empty/conflict/bookmarks as tab-separated fields after json
local LIST_TEMPLATE = 'json(self) ++ if(immutable, "\\t1", "\\t0") ++ if(empty, "\\t1", "\\t0") ++ if(conflict, "\\t1", "\\t0") ++ "\\t" ++ local_bookmarks.map(|b| b.name()).join(",") ++ "\\t" ++ remote_bookmarks.filter(|b| b.remote() != "git").map(|b| b.name() ++ "@" ++ b.remote()).join(",") ++ "\\n"'

--- Parse lines produced by LIST_TEMPLATE into entries
---@param lines string[]
---@return table[]
local function parse_enriched_lines(lines)
  local entries = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      local json_str, flags = line:match("^(.+})\t(.*)$")
      if json_str then
        local ok, obj = pcall(vim.json.decode, json_str)
        if ok and obj then
          local entry = M.json_to_entry(obj)
          local parts = vim.split(flags, "\t")
          entry.immutable = parts[1] == "1"
          entry.empty = parts[2] == "1"
          entry.conflict = parts[3] == "1"
          if parts[4] and parts[4] ~= "" then
            entry.bookmarks = vim.split(parts[4], ",")
          end
          if parts[5] and parts[5] ~= "" then
            entry.remote_bookmarks = vim.split(parts[5], ",")
          end
          table.insert(entries, entry)
        end
      end
    end
  end
  return entries
end

function M.list(revset, limit)
  local jj = require("neojj.lib.jj")
  local config = require("neojj.config")
  limit = limit or config.values.status.recent_commit_count
  revset = revset or ("ancestors(@, " .. limit .. ")")

  local result = jj.cli.log.no_graph
    .template(LIST_TEMPLATE)
    .revisions(revset)
    .call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  return parse_enriched_lines(result.stdout)
end

---Fetch changes with graph characters from `jj log -T 'json(self)'` (with graph).
---Each output line is either graph-only (connectors) or graph + JSON.
---@param revset? string Revset expression
---@param limit? number Max entries
---@return NeojjChangeLogEntry[]
function M.list_with_graph(revset, limit)
  local jj = require("neojj.lib.jj")
  local config = require("neojj.config")
  limit = limit or config.values.status.recent_commit_count
  revset = revset or ("ancestors(@, " .. limit .. ")")

  local result = jj.cli.log
    .template("json(self)")
    .revisions(revset)
    .call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  local entries = {}
  for _, line in ipairs(result.stdout) do
    local json_start = line:find("{")
    if json_start then
      local graph = line:sub(1, json_start - 1)
      local json_str = line:sub(json_start)
      local ok, obj = pcall(vim.json.decode, json_str)
      if ok and obj then
        local entry = M.json_to_entry(obj)
        entry.graph = graph
        entry.immutable = graph:match("◆") ~= nil
        entry.current_working_copy = graph:match("@") ~= nil
        table.insert(entries, entry)
      end
    else
      -- Graph-only line (connectors like │, ╭, ~, etc.)
      table.insert(entries, {
        change_id = nil,
        graph = line,
      })
    end
  end

  return entries
end

---Update repository state with recent changes
---@param state NeojjRepoState
function meta.update(state)
  local shell = require("neojj.lib.jj.shell")
  local config = require("neojj.config")
  local limit = config.values.status.recent_commit_count
  local revset = "ancestors(@, " .. limit .. ")"
  local lines, code = shell.exec({
    "jj", "--no-pager", "--color=never", "--ignore-working-copy",
    "log", "--no-graph", "-T", LIST_TEMPLATE, "-r", revset,
  }, state.worktree_root)

  local entries = (code == 0 and lines) and parse_enriched_lines(lines) or {}
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
