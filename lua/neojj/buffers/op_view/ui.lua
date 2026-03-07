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
  local id_hl = op.current and "NeoJJBranchHead" or "NeoJJObjectId"
  local marker = op.current and "@ " or "  "

  return row.tag("OpEntry")({
    text(marker, { highlight = op.current and "NeoJJBranchHead" or "NeoJJSubtleText" }),
    text(op.id, { highlight = id_hl }),
    text(" "),
    text(op.time or "", { highlight = "Special" }),
    text(" "),
    text(op.description or "", { highlight = "NeoJJGraphAuthor" }),
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
    text.highlight("NeoJJFloatHeaderHighlight")("Operations Log"),
  })
  table.insert(entries, 3, col { row { text("") } })

  table.insert(entries, col {
    row { text("") },
    row {
      text.highlight("NeoJJSubtleText")("u"),
      text(" = undo last op, "),
      text.highlight("NeoJJSubtleText")("R"),
      text(" = restore to op under cursor, "),
      text.highlight("NeoJJSubtleText")("q"),
      text("/"),
      text.highlight("NeoJJSubtleText")("<esc>"),
      text(" = close"),
    },
  })

  return entries
end

return M
