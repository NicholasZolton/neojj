local Color = require("neojj.lib.color").Color
local highlight = require("neojj.lib.hl")

describe("highlight palette", function()
  it("derives deleted-file red from ErrorMsg like Neogit", function()
    vim.api.nvim_set_hl(0, "Error", { fg = "#192330" })
    vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "NeojjChangeDeleted", {})

    highlight.setup { highlight = {} }

    local deleted = vim.api.nvim_get_hl(0, { name = "NeojjChangeDeleted", link = false })
    local expected = Color.from_hex("#e26886"):shade(-0.18):to_css()

    assert.are.equal(expected, string.format("#%06x", deleted.fg))
  end)
end)
