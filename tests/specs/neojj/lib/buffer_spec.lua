local eq = assert.are.same

local Buffer = require("neojj.lib.buffer")

describe("Buffer:add_line_highlight", function()
  it("uses a range extmark so word-level highlights can override it", function()
    local handle = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(handle, 0, -1, false, { "line one" })

    local buffer = Buffer:new(handle, -1)
    buffer:add_line_highlight(0, "NeojjDiffAddHighlight")

    local ns_id = buffer:get_namespace_id()
    local extmarks = vim.api.nvim_buf_get_extmarks(handle, ns_id, 0, -1, { details = true })
    eq(1, #extmarks)

    local opts = extmarks[1][4]
    eq("NeojjDiffAddHighlight", opts.hl_group)
    eq(1, opts.end_row)
    eq(0, opts.end_col)
    eq(true, opts.hl_eol)
    eq(190, opts.priority)
    eq(nil, opts.line_hl_group)
  end)
end)
