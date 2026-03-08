local Ui = require("neojj.lib.ui")
local util = require("neojj.lib.util")

local text = Ui.text
local col = Ui.col
local row = Ui.row
local map = util.map

local M = {}

---Render a single operation entry
---@param op table { id: string, description: string, time: string, tags: string, current: boolean }
function M.OpEntry(op)
  local id_hl = op.current and "NeojjBranchHead" or "NeojjObjectId"
  local marker = op.current and "@ " or "  "

  return row.tag("OpEntry")({
    text(marker, { highlight = op.current and "NeojjBranchHead" or "NeojjSubtleText" }),
    text(op.id, { highlight = id_hl }),
    text(" "),
    text(op.time or "", { highlight = "Special" }),
    text(" "),
    text(op.description and vim.split(op.description, "\n")[1] or "", { highlight = "NeojjGraphAuthor" }),
  }, {
    item = op,
    oid = op.id,
  })
end

---Render the operations view
---@param ops table[] List of operation entries
---@return table[]
function M.View(ops)
  local entries = map(ops, M.OpEntry)

  table.insert(entries, 1, col { row { text("") } })
  table.insert(entries, 2, row {
    text.highlight("NeojjFloatHeaderHighlight")("Operations Log"),
  })
  table.insert(entries, 3, col { row { text("") } })

  table.insert(entries, col {
    row { text("") },
    row {
      text.highlight("NeojjSubtleText")("u"),
      text(" = undo last op, "),
      text.highlight("NeojjSubtleText")("R"),
      text(" = restore to op under cursor, "),
      text.highlight("NeojjSubtleText")("q"),
      text("/"),
      text.highlight("NeojjSubtleText")("<esc>"),
      text(" = close"),
    },
  })

  return entries
end

return M
