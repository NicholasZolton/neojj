local M = {}

local Ui = require("neojj.lib.ui")
local util = require("neojj.lib.util")
local common_ui = require("neojj.buffers.common")

local Diff = common_ui.Diff
local text = Ui.text
local col = Ui.col
local row = Ui.row
local map = util.map

function M.OverviewFile(file)
  return row.tag("OverviewFile") {
    text.highlight("NeoJJFilePath")(file.path),
    text("  | "),
    text.highlight("Number")(util.pad_left(file.changes, 5)),
    text("  "),
    text.highlight("NeoJJDiffAdditions")(file.insertions),
    text.highlight("NeoJJDiffDeletions")(file.deletions),
  }
end

function M.CommitHeader(info)
  local header_items = {
    text.line_hl("NeoJJCommitViewHeader")("Change " .. (info.change_id or info.commit_arg or "")),
  }

  -- Show commit ID secondary
  if info.commit_id and info.commit_id ~= "" then
    table.insert(header_items, row {
      text.highlight("NeoJJSubtleText")("Commit ID:  "),
      text.highlight("NeoJJObjectId")(info.commit_id),
    })
  end

  -- Author info
  table.insert(header_items, row {
    text.highlight("NeoJJSubtleText")("Author:     "),
    text((info.author_name or "") .. " <" .. (info.author_email or "") .. ">"),
  })
  table.insert(header_items, row {
    text.highlight("NeoJJSubtleText")("Date:       "),
    text(info.author_date or ""),
  })

  -- Bookmarks
  if info.bookmarks and #info.bookmarks > 0 then
    table.insert(header_items, row {
      text.highlight("NeoJJSubtleText")("Bookmarks:  "),
      text.highlight("NeoJJBranch")(table.concat(info.bookmarks, ", ")),
    })
  end

  -- Status markers
  local status_parts = {}
  if info.conflict then
    table.insert(status_parts, "conflict")
  end
  if info.empty then
    table.insert(status_parts, "empty")
  end
  if #status_parts > 0 then
    table.insert(header_items, row {
      text.highlight("NeoJJSubtleText")("Status:     "),
      text.highlight("NeoJJDiffDeletions")(table.concat(status_parts, ", ")),
    })
  end

  return col(header_items)
end

function M.CommitView(info, overview, item_filter)
  if item_filter then
    overview.files = util.filter_map(overview.files, function(file)
      if vim.tbl_contains(item_filter, vim.trim(file.path)) then
        return file
      end
    end)

    info.diffs = util.filter_map(info.diffs, function(diff)
      if vim.tbl_contains(item_filter, vim.trim(diff.file)) then
        return diff
      end
    end)
  end

  return {
    M.CommitHeader(info),
    text(""),
    col(map(info.description, text), { highlight = "NeoJJCommitViewDescription", tag = "Description" }),
    text(""),
    text(overview.summary),
    col(map(overview.files, M.OverviewFile), { tag = "OverviewFileList" }),
    text(""),
    col(map(info.diffs, Diff), { tag = "DiffList" }),
  }
end

return M
