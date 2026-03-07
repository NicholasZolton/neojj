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

  -- jj show --stat output may have a header line, then file stats, then summary
  -- Find the first line with " | " pattern to start parsing files
  local start_idx = 1
  for i = 1, #raw do
    if raw[i]:match("|") then
      start_idx = i
      break
    end
  end

  for i = start_idx, #raw - 1 do
    local file = {}
    if raw[i] ~= "" then
      -- matches: tests/specs/neojj/popups/rebase_spec.lua | 2 +-
      file.path, file.changes, file.insertions, file.deletions = raw[i]:match(" (.*)%s+|%s+(%d+) ?(%+*)(%-*)")

      if vim.tbl_isempty(file) then
        -- matches: .../db/b8571c4f873daff059c04443077b43a703338a      | Bin 0 -> 192 bytes
        file.path, file.changes = raw[i]:match(" (.*)%s+|%s+(Bin .*)$")
      end

      if not vim.tbl_isempty(file) then
        table.insert(overview.files, file)
      end
    end
  end

  setmetatable(overview, { __index = CommitOverview })

  return overview
end

return M
