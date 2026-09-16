local Color = require("neojj.lib.color").Color
local highlight = require("neojj.lib.hl")

local function relative_luminance(color)
  local function linearize(channel)
    channel = channel / 255
    return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
  end

  local red = math.floor(color / 0x10000) % 0x100
  local green = math.floor(color / 0x100) % 0x100
  local blue = color % 0x100
  return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
end

local function contrast(foreground, background)
  local lighter = math.max(relative_luminance(foreground), relative_luminance(background))
  local darker = math.min(relative_luminance(foreground), relative_luminance(background))
  return (lighter + 0.05) / (darker + 0.05)
end

describe("highlight palette", function()
  it("scopes fallback colors to status highlights", function()
    vim.api.nvim_set_hl(0, "Error", { fg = "#192330" })
    vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "Macro", { fg = "#e26886" })
    vim.api.nvim_set_hl(0, "Identifier", { fg = "#719cd6" })
    vim.api.nvim_set_hl(0, "Operator", { fg = "#89ddff" })
    vim.api.nvim_set_hl(0, "NeojjGraphBlue", {})
    vim.api.nvim_set_hl(0, "NeojjChangeModified", {})
    vim.api.nvim_set_hl(0, "NeojjChangeDeleted", {})
    vim.api.nvim_set_hl(0, "NeojjObjectId", {})
    vim.api.nvim_set_hl(0, "NeojjBookmark", {})

    highlight.setup { highlight = {} }

    local modified = vim.api.nvim_get_hl(0, { name = "NeojjChangeModified", link = false })
    local deleted = vim.api.nvim_get_hl(0, { name = "NeojjChangeDeleted", link = false })
    local graph_blue = vim.api.nvim_get_hl(0, { name = "NeojjGraphBlue", link = false })
    local object_id = vim.api.nvim_get_hl(0, { name = "NeojjObjectId", link = false })
    local bookmark = vim.api.nvim_get_hl(0, { name = "NeojjBookmark", link = true })
    local expected_modified = Color.from_hex("#719cd6"):shade(-0.18):to_css()
    local expected_deleted = Color.from_hex("#e26886"):shade(-0.18):to_css()
    local expected_object_id = Color.from_hex("#89ddff"):shade(-0.18):to_css()

    assert.are.equal(expected_modified, string.format("#%06x", modified.fg))
    assert.are.equal(expected_deleted, string.format("#%06x", deleted.fg))
    assert.are_not.equal(modified.fg, deleted.fg)
    assert.are.equal("#e26886", string.format("#%06x", graph_blue.fg))
    assert.are.equal(expected_object_id, string.format("#%06x", object_id.fg))
    assert.are.equal("NeojjBranch", bookmark.link)
  end)

  for _, background in ipairs { "dark", "light" } do
    it("keeps inline diff text readable on " .. background .. " backgrounds", function()
      vim.o.background = background
      vim.api.nvim_set_hl(0, "Normal", {
        fg = background == "dark" and "#c8d3f5" or "#333333",
        bg = background == "dark" and "#1b1d2b" or "#f5f5f5",
      })
      vim.api.nvim_set_hl(0, "ErrorMsg", { fg = "#e26886" })
      vim.api.nvim_set_hl(0, "String", { fg = "#86aaec" })
      vim.api.nvim_set_hl(0, "NeojjDiffAddInline", {})
      vim.api.nvim_set_hl(0, "NeojjDiffDeleteInline", {})

      highlight.setup { highlight = {} }

      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      for _, group in ipairs { "NeojjDiffAddInline", "NeojjDiffDeleteInline" } do
        local colors = vim.api.nvim_get_hl(0, { name = group, link = false })
        assert.are.equal(normal.fg, colors.fg)
        assert.is_true(contrast(colors.fg, colors.bg) >= 4.5)
      end
    end)
  end
end)
