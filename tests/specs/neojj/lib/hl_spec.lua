local Color = require("neojj.lib.color").Color
local highlight = require("neojj.lib.hl")

describe("highlight palette", function()
  it("keeps file states and references distinguishable", function()
    vim.api.nvim_set_hl(0, "Error", { fg = "#192330" })
    vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "Macro", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "Identifier", { fg = "#719cd6" })
    vim.api.nvim_set_hl(0, "NeojjChangeModified", {})
    vim.api.nvim_set_hl(0, "NeojjChangeDeleted", {})
    vim.api.nvim_set_hl(0, "NeojjObjectId", {})
    vim.api.nvim_set_hl(0, "NeojjBookmark", {})

    highlight.setup { highlight = {} }

    local modified = vim.api.nvim_get_hl(0, { name = "NeojjChangeModified", link = false })
    local deleted = vim.api.nvim_get_hl(0, { name = "NeojjChangeDeleted", link = false })
    local object_id = vim.api.nvim_get_hl(0, { name = "NeojjObjectId", link = true })
    local bookmark = vim.api.nvim_get_hl(0, { name = "NeojjBookmark", link = true })
    local expected_modified = Color.from_hex("#719cd6"):shade(-0.18):to_css()
    local expected_deleted = Color.from_hex("#e26886"):shade(-0.18):to_css()

    assert.are.equal(expected_modified, string.format("#%06x", modified.fg))
    assert.are.equal(expected_deleted, string.format("#%06x", deleted.fg))
    assert.are_not.equal(modified.fg, deleted.fg)
    assert.are.equal("NeojjChangeIdRest", object_id.link)
    assert.are.equal("NeojjBranch", bookmark.link)
  end)
end)
