local util = require("neojj.lib.util")

local Commit = require("neojj.buffers.common").CommitEntry
local Graph = require("neojj.buffers.common").CommitGraph

local Ui = require("neojj.lib.ui")
local text = Ui.text
local col = Ui.col
local row = Ui.row

local M = {}

---@param commits NeojjChangeLogEntry[]
---@param remotes string[]
---@param args table
---@return table
function M.View(commits, remotes, args)
  args.details = true

  local graph = util.filter_map(commits, function(commit)
    if commit.change_id then
      return Commit(commit, remotes, args)
    elseif args.graph then
      local first_commit = commits[1]
      local padding = first_commit and first_commit.change_id
        and #string.sub(first_commit.change_id, 1, 12) + 1
        or 13
      return Graph(commit, padding)
    end
  end)

  table.insert(graph, 1, col { row { text("") } })

  table.insert(
    graph,
    col {
      row {
        text.highlight("NeojjGraphBoldBlue")("Type"),
        text.highlight("NeojjGraphBoldCyan")(" + "),
        text.highlight("NeojjGraphBoldBlue")("to show more history"),
      },
    }
  )

  return graph
end

return M
