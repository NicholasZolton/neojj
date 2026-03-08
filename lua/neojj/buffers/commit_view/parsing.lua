local M = {}

local util = require("neojj.lib.util")

local CommitOverview = {}

---@param raw table
---@return CommitOverview
function M.parse_commit_overview(raw)
  if not raw or #raw == 0 then
    return {
      summary = "",
      files = {},
    }
  end

  local overview = {
    summary = util.trim(raw[#raw]),
    files = {},
  }

  -- jj show --stat output: header lines, blank, description, blank, stat file lines, summary
  -- Find stat file lines by searching backwards from the summary line.
  -- The summary line (last) is "N files changed, ..." — stat file lines are just above it.
  local end_idx = #raw - 1
  local start_idx = nil

  for i = end_idx, 1, -1 do
    if raw[i]:match("%s*|%s+%d") or raw[i]:match("%s*|%s+Bin ") then
      start_idx = i
    else
      if start_idx then
        break
      end
    end
  end

  if not start_idx then
    setmetatable(overview, { __index = CommitOverview })
    return overview
  end

  for i = start_idx, end_idx do
    local file = {}
    if raw[i] ~= "" then
      -- matches: lua/neojj/config.lua              | 10 +++++-----
      -- jj stat lines have no leading space, so match from start
      file.path, file.changes, file.insertions, file.deletions =
        raw[i]:match("^(.-)%s+|%s+(%d+) ?(%+*)(%-*)")

      if vim.tbl_isempty(file) then
        -- matches: .../db/b8571c4f873daff059c04443077b43a703338a      | Bin 0 -> 192 bytes
        file.path, file.changes = raw[i]:match("^(.-)%s+|%s+(Bin .*)$")
      end

      if not vim.tbl_isempty(file) then
        -- Trim leading/trailing whitespace from path
        file.path = util.trim(file.path)
        table.insert(overview.files, file)
      end
    end
  end

  setmetatable(overview, { __index = CommitOverview })

  return overview
end

return M
