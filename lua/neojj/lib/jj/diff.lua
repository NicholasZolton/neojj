local M = {}

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
