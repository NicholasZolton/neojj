---@alias CommitLogEntry NeojjChangeLogEntry

---@class NeojjLog
---@field parse_json_objects fun(text: string): table[]
---@field json_to_entry fun(obj: table): NeojjChangeLogEntry
---@field parse_graph fun(lines: string[]): NeojjChangeLogEntry[]
---@field group_divergent fun(entries: NeojjChangeLogEntry[]): NeojjChangeLogEntry[]
---@field merge_unique_by_commit_id fun(primary: NeojjChangeLogEntry[], additional: NeojjChangeLogEntry[]): NeojjChangeLogEntry[]
---@field list fun(revset?: string, limit?: integer): NeojjChangeLogEntry[]
---@field parse_with_graph_line fun(line: string): NeojjChangeLogEntry?
---@field list_with_graph fun(revset?: string, limit?: integer): NeojjChangeLogEntry[]
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
    divergent = false,
    change_offset = nil,
    variants = nil,
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

-- Template that appends display state as tab-separated fields after json
local LIST_TEMPLATE =
  'json(self) ++ if(immutable, "\\t1", "\\t0") ++ if(empty, "\\t1", "\\t0") ++ if(conflict, "\\t1", "\\t0") ++ if(divergent, "\\t1", "\\t0") ++ "\\t" ++ local_bookmarks.map(|b| b.name()).join(",") ++ "\\t" ++ remote_bookmarks.filter(|b| b.remote() != "git").map(|b| b.name() ++ "@" ++ b.remote()).join(",") ++ "\\t" ++ change_id.shortest(8).prefix() ++ "\\t" ++ self.change_offset() ++ if(current_working_copy, "\\t1", "\\t0") ++ "\\n"'

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
          entry.divergent = parts[4] == "1"
          if parts[5] and parts[5] ~= "" then
            entry.bookmarks = vim.split(parts[5], ",")
          end
          if parts[6] and parts[6] ~= "" then
            entry.remote_bookmarks = vim.split(parts[6], ",")
          end
          if parts[7] and parts[7] ~= "" then
            entry.shortest_prefix = parts[7]
          end
          -- jj's `self.change_offset()` returns 0 for non-divergent commits; only
          -- carry it through for actual variants so the field's "this is a divergent
          -- variant" semantics are preserved.
          if entry.divergent and parts[8] and parts[8] ~= "" then
            entry.change_offset = tonumber(parts[8])
          end
          entry.current_working_copy = parts[9] == "1"
          table.insert(entries, entry)
        end
      end
    end
  end
  return entries
end

---Synthesize a parent entry from a list of divergent variants. Variants must share change_id.
---@param variants NeojjChangeLogEntry[]
---@return NeojjChangeLogEntry
local function synthesize_parent(variants)
  local lead = variants[1]
  local bookmarks = {}
  local seen = {}
  local working_copy = false
  local immutable = false
  for _, v in ipairs(variants) do
    if v.current_working_copy then
      working_copy = true
    end
    if v.immutable then
      immutable = true
    end
    for _, b in ipairs(v.bookmarks or {}) do
      if not seen[b] then
        seen[b] = true
        table.insert(bookmarks, b)
      end
    end
  end
  return {
    change_id = lead.change_id,
    commit_id = "",
    description = "",
    author_name = "",
    author_email = "",
    author_date = "",
    bookmarks = bookmarks,
    empty = false,
    conflict = false,
    immutable = immutable,
    current_working_copy = working_copy,
    graph = lead.graph,
    divergent = true,
    change_offset = nil,
    variants = variants,
    shortest_prefix = lead.shortest_prefix,
  }
end

---Group divergent entries (sharing a change_id) under a synthesized parent.
---Single-entry "groups" pass through unchanged. Order of non-divergent
---entries is preserved; the parent takes the slot of the first variant.
---@param entries NeojjChangeLogEntry[]
---@return NeojjChangeLogEntry[]
function M.group_divergent(entries)
  -- First pass: collect indices per divergent change_id (in original order)
  local groups = {}
  for i, e in ipairs(entries) do
    if e and e.divergent and e.change_id and e.change_id ~= "" then
      groups[e.change_id] = groups[e.change_id] or {}
      table.insert(groups[e.change_id], i)
    end
  end

  -- Decide which slots are removed and where parents go
  local removed = {}
  local parent_at = {} -- index -> parent entry
  for _, indices in pairs(groups) do
    if #indices >= 2 then
      local variants = {}
      for _, idx in ipairs(indices) do
        table.insert(variants, vim.deepcopy(entries[idx]))
      end
      -- Sort by jj's authoritative change_offset so the rendered /0, /1, ...
      -- order matches what `jj log` shows. Falls back to original index when
      -- offset is missing (shouldn't happen for divergent entries from the
      -- template, but defensive against older callers that build entries by hand).
      table.sort(variants, function(a, b)
        return (a.change_offset or 0) < (b.change_offset or 0)
      end)
      parent_at[indices[1]] = synthesize_parent(variants)
      for k = 2, #indices do
        removed[indices[k]] = true
      end
    end
  end

  -- Second pass: emit, replacing/skipping as decided
  local out = {}
  local just_removed = false
  for i, e in ipairs(entries) do
    if removed[i] then
      just_removed = true
    elseif parent_at[i] then
      table.insert(out, parent_at[i])
      just_removed = false
    elseif e and e.change_id == nil then
      -- graph-only connector: drop it if it immediately follows a removed slot
      if not just_removed then
        table.insert(out, e)
      end
      -- keep just_removed false on connector pass-through
      just_removed = false
    else
      table.insert(out, e)
      just_removed = false
    end
  end

  return out
end

---Append entries from `additional` to `primary`, skipping any whose `commit_id`
---already appears in `primary`. Mutates and returns `primary` for convenience.
---Empty/nil commit_ids are skipped on both sides.
---@param primary NeojjChangeLogEntry[]
---@param additional NeojjChangeLogEntry[]
---@return NeojjChangeLogEntry[]
function M.merge_unique_by_commit_id(primary, additional)
  local seen = {}
  for _, e in ipairs(primary) do
    if e.commit_id and e.commit_id ~= "" then
      seen[e.commit_id] = true
    end
  end
  for _, e in ipairs(additional) do
    if e.commit_id and e.commit_id ~= "" and not seen[e.commit_id] then
      seen[e.commit_id] = true
      table.insert(primary, e)
    end
  end
  return primary
end

---Fetch recent changes via JSON template (no graph)
---@param revset? string Revset expression (default: ancestors(@, N))
---@param limit? number Max entries
---@return NeojjChangeLogEntry[]
function M.list(revset, limit)
  local jj = require("neojj.lib.jj")
  local config = require("neojj.config")
  limit = limit or config.values.status.recent_commit_count

  local builder = jj.cli.log.no_graph.template(LIST_TEMPLATE)
  if revset and revset ~= "" then
    builder = builder.revisions(revset)
  end
  if limit and limit > 0 then
    builder = builder.limit(limit)
  end
  local result = builder.call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  return M.group_divergent(parse_enriched_lines(result.stdout))
end

---Parse a single line of `jj log -T 'json(self) ++ "\tdivergent\t" ++ N or "\t\t"'` output.
---Trailing format is `\t<divergent>\t<change_offset>` where `<divergent>` is
---literally "divergent" or empty, and `<change_offset>` is jj's variant index
---for divergent commits (empty otherwise).
---@param line string
---@return NeojjChangeLogEntry
function M.parse_with_graph_line(line)
  local json_start = line:find("{")
  if not json_start then
    return { change_id = nil, graph = line }
  end
  local graph = line:sub(1, json_start - 1)
  local rest = line:sub(json_start)

  -- Find the LAST '}' so we don't mistakenly split inside a JSON string.
  local last_brace = rest:match("^.*()}")
  if not last_brace then
    return { change_id = nil, graph = line }
  end
  local json_str = rest:sub(1, last_brace)
  local trailing = rest:sub(last_brace + 1)

  local ok, obj = pcall(vim.json.decode, json_str)
  if not ok or not obj then
    return { change_id = nil, graph = line }
  end

  local entry = M.json_to_entry(obj)
  entry.graph = graph
  local trailing_parts = vim.split(trailing, "\t", { plain = true })
  entry.divergent = trailing_parts[2] == "divergent"
  if entry.divergent and trailing_parts[3] and trailing_parts[3] ~= "" then
    entry.change_offset = tonumber(trailing_parts[3])
  end
  entry.immutable = graph:match("◆") ~= nil
  entry.current_working_copy = graph:match("@") ~= nil
  return entry
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

  local builder = jj.cli.log.template(
    'json(self) ++ "\\t" ++ if(divergent, "divergent", "") ++ "\\t" ++ if(divergent, self.change_offset(), "")'
  )
  if revset and revset ~= "" then
    builder = builder.revisions(revset)
  end
  if limit and limit > 0 then
    builder = builder.limit(limit)
  end
  local result = builder.call { hidden = true, trim = true }

  if not result or result.code ~= 0 then
    return {}
  end

  local entries = {}
  for _, line in ipairs(result.stdout) do
    table.insert(entries, M.parse_with_graph_line(line))
  end
  return M.group_divergent(entries)
end

---Update repository state with recent changes
---@param state NeojjRepoState
function meta.update(state)
  local shell = require("neojj.lib.jj.shell")
  local config = require("neojj.config")
  local limit = config.values.status.recent_commit_count
  local revset = "ancestors(@, " .. limit .. ")"
  local lines, code = shell.exec({
    "jj",
    "--no-pager",
    "--color=never",
    "--ignore-working-copy",
    "log",
    "--no-graph",
    "-T",
    LIST_TEMPLATE,
    "-r",
    revset,
  }, state.worktree_root)

  local entries = (code == 0 and lines) and parse_enriched_lines(lines) or {}

  -- Expand divergent groups: ancestors(@, N) only walks @'s parent chain so
  -- divergent siblings (same change_id, different parent) are missed. Issue a
  -- second query for change_id(<id>) of each divergent change_id we saw.
  local divergent_revsets = {}
  local seen_change_ids = {}
  for _, e in ipairs(entries) do
    if e.divergent and e.change_id and e.change_id ~= "" and not seen_change_ids[e.change_id] then
      seen_change_ids[e.change_id] = true
      table.insert(divergent_revsets, "change_id(" .. e.change_id .. ")")
    end
  end

  if #divergent_revsets > 0 then
    local sibling_revset = table.concat(divergent_revsets, " | ")
    local sibling_lines, sibling_code = shell.exec({
      "jj",
      "--no-pager",
      "--color=never",
      "--ignore-working-copy",
      "log",
      "--no-graph",
      "-T",
      LIST_TEMPLATE,
      "-r",
      sibling_revset,
    }, state.worktree_root)
    if sibling_code == 0 and sibling_lines then
      local sibling_entries = parse_enriched_lines(sibling_lines)
      M.merge_unique_by_commit_id(entries, sibling_entries)
    end
  end

  state.recent.items = M.group_divergent(entries)

  -- Enrich head and parent from log data (description, shortest_prefix).
  -- Match by commit_id so divergent variants (which share a change_id) resolve
  -- to the right entry. state.{head,parent}.commit_id is the short prefix from
  -- `jj status`; entry.commit_id is the full hash from the JSON template.
  if #entries > 0 then
    for _, entry in ipairs(entries) do
      if
        state.head.commit_id ~= ""
        and entry.commit_id ~= ""
        and entry.commit_id:find(state.head.commit_id, 1, true) == 1
      then
        if
          entry.description ~= "" and (state.head.description == "" or state.head.description:match("^%("))
        then
          state.head.description = entry.description
        end
        if entry.shortest_prefix then
          state.head.shortest_prefix = entry.shortest_prefix
        end
      end
      if
        state.parent.commit_id ~= ""
        and entry.commit_id ~= ""
        and entry.commit_id:find(state.parent.commit_id, 1, true) == 1
      then
        if entry.shortest_prefix then
          state.parent.shortest_prefix = entry.shortest_prefix
        end
      end
    end
  end
end

M.meta = meta
M.parse_enriched_lines = parse_enriched_lines

return M
