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
  before_each(function()
    vim.o.background = "dark"
    vim.cmd("highlight clear")
  end)

  local function assert_inline_contrast()
    for _, kind in ipairs { "Add", "Delete" } do
      local inline = vim.api.nvim_get_hl(0, { name = "NeojjDiff" .. kind .. "Inline", link = false })
      local line = vim.api.nvim_get_hl(0, { name = "NeojjDiff" .. kind, link = false })
      assert.is_true(contrast(inline.bg, line.bg) >= 2, kind .. " inline background should stand out")
      assert.is_true(contrast(inline.fg, inline.bg) >= 4.5, kind .. " inline text should remain readable")
    end
  end

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
      vim.api.nvim_set_hl(0, "ErrorMsg", { fg = background == "dark" and "#e26886" or "#b4233f" })
      vim.api.nvim_set_hl(0, "String", { fg = background == "dark" and "#8bd49c" or "#217a3c" })
      vim.api.nvim_set_hl(0, "NeojjDiffAddInline", {})
      vim.api.nvim_set_hl(0, "NeojjDiffDeleteInline", {})

      highlight.setup { highlight = {} }

      assert_inline_contrast()
      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      for _, group in ipairs { "NeojjDiffAddInline", "NeojjDiffDeleteInline" } do
        local colors = vim.api.nvim_get_hl(0, { name = group, link = false })
        assert.are_not.equal(normal.fg, colors.fg)
        assert.is_true(contrast(colors.fg, colors.bg) >= 4.5)
      end

      local addition = vim.api.nvim_get_hl(0, { name = "NeojjDiffAddInline", link = false })
      local deletion = vim.api.nvim_get_hl(0, { name = "NeojjDiffDeleteInline", link = false })
      assert.are_not.equal(addition.fg, deletion.fg)
      assert.are_not.equal(addition.bg, deletion.bg)
    end)
  end

  for _, scheme in ipairs { "blue", "vim" } do
    it("distinguishes inline changes from diff lines with stock " .. scheme, function()
      vim.cmd.colorscheme(scheme)
      highlight.setup { highlight = {} }
      assert_inline_contrast()
    end)
  end

  it("uses overridden diff line backgrounds when ensuring inline contrast", function()
    highlight.setup {
      highlight = { line_green = "#777777", line_red = "#888888" },
    }
    assert_inline_contrast()
  end)

  it("resolves named diff line colors before calculating inline contrast", function()
    highlight.setup {
      highlight = { line_green = "pink", line_red = "LightBlue" },
    }
    local addition = vim.api.nvim_get_hl(0, { name = "NeojjDiffAdd", link = false })
    local deletion = vim.api.nvim_get_hl(0, { name = "NeojjDiffDelete", link = false })
    assert.are.equal(vim.api.nvim_get_color_by_name("pink"), addition.bg)
    assert.are.equal(vim.api.nvim_get_color_by_name("LightBlue"), deletion.bg)
    assert_inline_contrast()
  end)

  it("leaves generated inline backgrounds unchanged when they already stand out", function()
    vim.api.nvim_set_hl(0, "Normal", { bg = "#ffffff" })
    highlight.setup {
      highlight = {
        green = "#00ff00",
        red = "#ff0000",
        line_green = "#000000",
        line_red = "#000000",
      },
    }
    local addition = vim.api.nvim_get_hl(0, { name = "NeojjDiffAddInline", link = false })
    local deletion = vim.api.nvim_get_hl(0, { name = "NeojjDiffDeleteInline", link = false })
    assert.are.equal(0x8cff8c, addition.bg)
    assert.are.equal(0xff8c8c, deletion.bg)
    assert_inline_contrast()
  end)

  it("preserves explicit inline background overrides even with low contrast", function()
    highlight.setup {
      highlight = {
        line_green = "#777777",
        line_red = "#888888",
        inline_green = "#777777",
        inline_red = "#888888",
      },
    }
    local addition = vim.api.nvim_get_hl(0, { name = "NeojjDiffAddInline", link = false })
    local deletion = vim.api.nvim_get_hl(0, { name = "NeojjDiffDeleteInline", link = false })
    assert.are.equal(0x777777, addition.bg)
    assert.are.equal(0x888888, deletion.bg)
    assert.is_true(contrast(addition.fg, addition.bg) >= 4.5)
    assert.is_true(contrast(deletion.fg, deletion.bg) >= 4.5)
  end)

  it("preserves theme-provided inline highlight groups", function()
    vim.api.nvim_set_hl(0, "NeojjDiffAddInline", { bg = "#123456", bold = true })
    vim.api.nvim_set_hl(0, "NeojjDiffDeleteInline", { link = "DiffText" })
    local addition = vim.api.nvim_get_hl(0, { name = "NeojjDiffAddInline" })
    local deletion = vim.api.nvim_get_hl(0, { name = "NeojjDiffDeleteInline" })
    highlight.setup { highlight = {} }
    assert.are.same(addition, vim.api.nvim_get_hl(0, { name = "NeojjDiffAddInline" }))
    assert.are.same(deletion, vim.api.nvim_get_hl(0, { name = "NeojjDiffDeleteInline" }))
  end)
end)
