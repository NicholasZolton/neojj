local insert = table.insert

local M = {}

-- ============================================================
-- Diff parsing (reused from git/diff.lua — jj diff --git is identical format)
-- ============================================================

---@param output string[]
---@return string[], number
local function build_diff_header(output)
  local header = {}
  local start_idx = 1

  for i = start_idx, #output do
    local line = output[i]
    if line:match("^@@@*.*@@@*") then
      start_idx = i
      break
    end

    insert(header, line)
  end

  return header, start_idx
end

---@param header string[]
---@param kind string
---@return string
local function build_file(header, kind)
  if kind == "modified" then
    return header[3] and header[3]:match("%-%-%- ./(.*)" ) or ""
  elseif kind == "renamed" then
    local from = header[3] and header[3]:match("rename from (.*)") or ""
    local to = header[4] and header[4]:match("rename to (.*)") or ""
    return ("%s -> %s"):format(from, to)
  elseif kind == "new file" then
    return header[5] and header[5]:match("%+%+%+ b/(.*)") or ""
  elseif kind == "deleted file" then
    return header[4] and header[4]:match("%-%-%- a/(.*)") or ""
  else
    return ""
  end
end

---@param header string[]
---@return string, string[]
local function build_kind(header)
  local kind = ""
  local info = {}
  local header_count = #header

  if header_count >= 4 and header[2]:match("^similarity index") then
    kind = "renamed"
    info = { header[3], header[4] }
  elseif header_count == 4 then
    kind = "modified"
  elseif header_count == 5 then
    kind = header[2]:match("(.*) mode %d+") or header[3]:match("(.*) mode %d+") or ""
  end

  return kind, info
end

---@param output string[]
---@param start_idx number
---@return string[]
local function build_lines(output, start_idx)
  local lines = {}

  if start_idx == 1 then
    lines = output
  else
    for i = start_idx, #output do
      insert(lines, output[i])
    end
  end

  return lines
end

---Simple DJB2 hash — pure Lua, safe in fast event context
---@param content string[]
---@return string
local function hunk_hash(content)
  local h = 5381
  for _, line in ipairs(content) do
    for i = 1, #line do
      h = ((h * 33) + line:byte(i)) % 0x100000000
    end
    h = ((h * 33) + 10) % 0x100000000 -- newline separator
  end
  return string.format("%08x", h)
end

---@param lines string[]
---@return Hunk[]
local function build_hunks(lines)
  local hunks = {}
  local hunk = nil
  local hunk_content = {}

  for i = 1, #lines do
    local line = lines[i]
    if not line:match("^%+%+%+") then
      local index_from, index_len, disk_from, disk_len

      if line:match("^@@@") then
        index_from, index_len, disk_from, disk_len = line:match("@@@* %-(%d+),?(%d*) .* %+(%d+),?(%d*) @@@*")
      else
        index_from, index_len, disk_from, disk_len = line:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      end

      if index_from then
        if hunk ~= nil then
          hunk.hash = hunk_hash(hunk_content)
          hunk_content = {}
          insert(hunks, hunk)
        end

        hunk = {
          index_from = tonumber(index_from),
          index_len = tonumber(index_len) or 1,
          disk_from = tonumber(disk_from),
          disk_len = tonumber(disk_len) or 1,
          line = line,
          diff_from = i,
          diff_to = i,
        }
      else
        insert(hunk_content, line)

        if hunk then
          hunk.diff_to = hunk.diff_to + 1
        end
      end
    end
  end

  if hunk then
    hunk.hash = hunk_hash(hunk_content)
    insert(hunks, hunk)
  end

  for _, h in ipairs(hunks) do
    h.lines = {}
    for i = h.diff_from + 1, h.diff_to do
      insert(h.lines, lines[i])
    end

    h.length = h.diff_to - h.diff_from
  end

  return hunks
end

---Parse raw diff output into a Diff object
---@param raw_diff string[]
---@return Diff
function M.parse(raw_diff)
  local header, start_idx = build_diff_header(raw_diff)
  local lines = build_lines(raw_diff, start_idx)
  local hunks = build_hunks(lines)
  local kind, info = build_kind(header)
  local file = build_file(header, kind)

  for _, hunk in ipairs(hunks) do
    hunk.file = file
  end

  return {
    kind = kind,
    lines = lines,
    file = file,
    info = info,
    stats = { additions = 0, deletions = 0 },
    hunks = hunks,
  }
end

-- ============================================================
-- Lazy diff loading via metatable (attaches to file items)
-- ============================================================

---Attach lazy diff loading to a file item
---When item.diff is accessed, it runs `jj diff --git` for that file and parses the result.
---Uses --ignore-working-copy because the status refresh already triggered a snapshot.
---Supports both sync (vim.system:wait) and async (plenary.async) contexts.
---@param item NeoJJFileItem
function M.build(item)
  local empty_diff = {
    kind = "modified",
    lines = {},
    file = item.name,
    info = {},
    stats = { additions = 0, deletions = 0 },
    hunks = {},
  }

  setmetatable(item, {
    __index = function(self, method)
      if method == "diff" then
        local cwd
        local ok, jj_mod = pcall(require, "neojj.lib.jj")
        if ok then
          local rok, repo = pcall(function() return jj_mod.repo end)
          if rok and repo then
            cwd = repo.worktree_root
          end
        end

        local cmd = { "jj", "--no-pager", "--color=never", "--ignore-working-copy", "diff", "--git", "--", item.name }
        local opts = { cwd = cwd or vim.fn.getcwd(), text = true }

        -- Use async wrapper if in a coroutine, else fall back to sync
        local result
        if coroutine.running() then
          local a = require("plenary.async")
          local jj_system = a.wrap(function(c, o, cb)
            vim.system(c, o, function(r) vim.schedule(function() cb(r) end) end)
          end, 3)
          result = jj_system(cmd, opts)
        else
          result = vim.system(cmd, opts):wait()
        end

        if result.code == 0 and result.stdout and result.stdout ~= "" then
          local lines = vim.split(result.stdout, "\n", { trimempty = true })
          self.diff = M.parse(lines)
        else
          self.diff = empty_diff
        end

        return self.diff
      end
    end,
  })
end

-- ============================================================
-- High-level diff functions
-- ============================================================

---Get diff for the working copy change (or a specific revision)
---@param revision? string Revision to diff (default: working copy @)
---@return string[] Raw diff lines in git format
function M.raw(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.git
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff between two revisions
---@param from string Source revision
---@param to string Target revision
---@return string[] Raw diff lines in git format
function M.raw_range(from, to)
  local jj = require("neojj.lib.jj")
  local result = jj.cli.diff.git.from(from).to(to).call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff summary for a revision
---@param revision? string
---@return string[] Summary lines (e.g., "M file.txt")
function M.summary(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.summary
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Get diff stat
---@param revision? string
---@return string[] Stat lines
function M.stat(revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.stat
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

---Build diff for a specific file item (lazy loading)
---@param item NeoJJFileItem
---@param revision? string
---@return string[] Raw diff lines for this file
function M.file_diff(item, revision)
  local jj = require("neojj.lib.jj")
  local builder = jj.cli.diff.git
  if revision then
    builder = builder.revision(revision)
  end
  local result = builder.files(item.name).call { hidden = true, trim = true }
  if result and result.code == 0 then
    return result.stdout
  end
  return {}
end

return M
