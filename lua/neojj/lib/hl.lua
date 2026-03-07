--#region TYPES

---@class HiSpec
---@field fg string
---@field bg string
---@field gui string
---@field sp string
---@field blend integer
---@field default boolean

---@class HiLinkSpec
---@field force boolean
---@field default boolean

--#endregion

local Color = require("neojj.lib.color").Color
local hl_store
local M = {}

---@param dec number
---@return string
local function to_hex(dec)
  local hex = string.format("%x", dec)
  if #hex < 6 then
    return string.rep("0", 6 - #hex) .. hex
  else
    return hex
  end
end

---@param name string Syntax group name.
---@return string|nil
local function get_fg(name)
  local color = vim.api.nvim_get_hl(0, { name = name })
  if color["link"] then
    return get_fg(color["link"])
  elseif color["reverse"] and color["bg"] then
    return "#" .. to_hex(color["bg"])
  elseif color["fg"] then
    return "#" .. to_hex(color["fg"])
  end
end

---@param name string Syntax group name.
---@return string|nil
local function get_bg(name)
  local color = vim.api.nvim_get_hl(0, { name = name })
  if color["link"] then
    return get_bg(color["link"])
  elseif color["reverse"] and color["fg"] then
    return "#" .. to_hex(color["fg"])
  elseif color["bg"] then
    return "#" .. to_hex(color["bg"])
  end
end

---@class NeoJJColorPalette
---@field bg0        string  Darkest background color
---@field bg1        string  Second darkest background color
---@field bg2        string  Second lightest background color
---@field bg3        string  Lightest background color
---@field grey       string  middle grey shade for foreground
---@field white      string  Foreground white (main text)
---@field red        string  Foreground red
---@field bg_red     string  Background red
---@field line_red   string  Cursor line highlight for red regions, like deleted hunks
---@field orange     string  Foreground orange
---@field bg_orange  string  background orange
---@field yellow     string  Foreground yellow
---@field bg_yellow  string  background yellow
---@field green      string  Foreground green
---@field bg_green   string  Background green
---@field line_green string  Cursor line highlight for green regions, like added hunks
---@field cyan       string  Foreground cyan
---@field bg_cyan    string  Background cyan
---@field blue       string  Foreground blue
---@field bg_blue    string  Background blue
---@field purple     string  Foreground purple
---@field bg_purple  string  Background purple
---@field md_purple  string  Background _medium_ purple. Lighter than bg_purple.
---@field italic     boolean enable italics?
---@field bold       boolean enable bold?
---@field underline  boolean enable underline?

-- stylua: ignore start
---@param config NeoJJConfig
---@return NeoJJColorPalette
local function make_palette(config)
  local bg        = Color.from_hex(get_bg("Normal") or (vim.o.bg == "dark" and "#22252A" or "#eeeeee"))
  local fg        = Color.from_hex((vim.o.bg == "dark" and "#fcfcfc" or "#22252A"))
  local red       = Color.from_hex(config.highlight.red    or get_fg("Error")       or "#E06C75")
  local orange    = Color.from_hex(config.highlight.orange or get_fg("SpecialChar") or "#ffcb6b")
  local yellow    = Color.from_hex(config.highlight.yellow or get_fg("PreProc")     or "#FFE082")
  local green     = Color.from_hex(config.highlight.green  or get_fg("String")      or "#C3E88D")
  local cyan      = Color.from_hex(config.highlight.cyan   or get_fg("Operator")    or "#89ddff")
  local blue      = Color.from_hex(config.highlight.blue   or get_fg("Macro")       or "#82AAFF")
  local purple    = Color.from_hex(config.highlight.purple or get_fg("Include")     or "#C792EA")

  local bg_factor = vim.o.bg == "dark" and 1 or -1

  local default   = {
    bg0        = bg:to_css(),
    bg1        = bg:shade(bg_factor * 0.019):to_css(),
    bg2        = bg:shade(bg_factor * 0.065):to_css(),
    bg3        = bg:shade(bg_factor * 0.11):to_css(),
    grey       = bg:shade(bg_factor * 0.4):to_css(),
    white      = fg:to_css(),
    red        = red:to_css(),
    bg_red     = red:shade(bg_factor * -0.18):to_css(),
    line_red   = get_bg("DiffDelete") or red:shade(bg_factor * -0.6):set_saturation(0.4):to_css(),
    orange     = orange:to_css(),
    bg_orange  = orange:shade(bg_factor * -0.17):to_css(),
    yellow     = yellow:to_css(),
    bg_yellow  = yellow:shade(bg_factor * -0.17):to_css(),
    green      = green:to_css(),
    bg_green   = green:shade(bg_factor * -0.18):to_css(),
    line_green = get_bg("DiffAdd") or green:shade(bg_factor * -0.72):set_saturation(0.2):to_css(),
    cyan       = cyan:to_css(),
    bg_cyan    = cyan:shade(bg_factor * -0.18):to_css(),
    blue       = blue:to_css(),
    bg_blue    = blue:shade(bg_factor * -0.18):to_css(),
    purple     = purple:to_css(),
    bg_purple  = purple:shade(bg_factor * -0.18):to_css(),
    md_purple  = purple:shade(0.18):to_css(),
    italic     = true,
    bold       = true,
    underline  = true,
  }

  return vim.tbl_extend("keep", config.highlight or {}, default)
end
-- stylua: ignore end

--- @param hl_name string
--- @return boolean
local function is_set(hl_name)
  local exists, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_name })
  if not exists then
    return false
  end

  return not vim.tbl_isempty(hl)
end

---@param config NeoJJConfig
function M.setup(config)
  local palette = make_palette(config)

  -- stylua: ignore
  hl_store = {
    NeoJJGraphAuthor              = { fg = palette.orange , ctermfg = 3 },
    NeoJJGraphRed                 = { fg = palette.red, ctermfg = 1 },
    NeoJJGraphWhite               = { fg = palette.white, ctermfg =  7 },
    NeoJJGraphYellow              = { fg = palette.yellow, ctermfg = 3 },
    NeoJJGraphGreen               = { fg = palette.green, ctermfg = 2 },
    NeoJJGraphCyan                = { fg = palette.cyan, ctermfg = 6 },
    NeoJJGraphBlue                = { fg = palette.blue, ctermfg = 4 },
    NeoJJGraphPurple              = { fg = palette.purple, ctermfg = 5 },
    NeoJJGraphGray                = { fg = palette.grey, ctermfg = 7 },
    NeoJJGraphOrange              = { fg = palette.orange, ctermfg = 3 },
    NeoJJGraphBoldOrange          = { fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    NeoJJGraphBoldRed             = { fg = palette.red, bold = palette.bold, ctermfg = 1 },
    NeoJJGraphBoldWhite           = { fg = palette.white, bold = palette.bold, ctermfg = 7 },
    NeoJJGraphBoldYellow          = { fg = palette.yellow, bold = palette.bold, ctermfg = 3 },
    NeoJJGraphBoldGreen           = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeoJJGraphBoldCyan            = { fg = palette.cyan, bold = palette.bold, ctermfg = 6 },
    NeoJJGraphBoldBlue            = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    NeoJJGraphBoldPurple          = { fg = palette.purple, bold = palette.bold, ctermfg = 5 },
    NeoJJGraphBoldGray            = { fg = palette.grey, bold = palette.bold, ctermfg = 7 },
    NeoJJSubtleText               = { link = "Comment" },
    NeoJJSignatureGood            = { link = "NeoJJGraphGreen" },
    NeoJJSignatureBad             = { link = "NeoJJGraphBoldRed" },
    NeoJJSignatureMissing         = { link = "NeoJJGraphPurple" },
    NeoJJSignatureNone            = { link = "NeoJJSubtleText" },
    NeoJJSignatureGoodUnknown     = { link = "NeoJJGraphBlue" },
    NeoJJSignatureGoodExpired     = { link = "NeoJJGraphOrange" },
    NeoJJSignatureGoodExpiredKey  = { link = "NeoJJGraphYellow" },
    NeoJJSignatureGoodRevokedKey  = { link = "NeoJJGraphRed" },
    NeoJJNormal                   = { link = "Normal" },
    NeoJJNormalFloat              = { link = "NeoJJNormal" },
    NeoJJFloatBorder              = { link = "NeoJJNormalFloat" },
    NeoJJSignColumn               = { fg = "None", bg = "None" },
    NeoJJCursorLine               = { link = "CursorLine" },
    NeoJJCursorLineNr             = { link = "CursorLineNr" },
    NeoJJHunkMergeHeader          = { fg = palette.bg2, bg = palette.grey, bold = palette.bold, ctermfg = 4 },
    NeoJJHunkMergeHeaderHighlight = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    NeoJJHunkMergeHeaderCursor    = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    NeoJJHunkHeader               = { fg = palette.bg0, bg = palette.grey, bold = palette.bold, ctermfg = 3 },
    NeoJJHunkHeaderHighlight      = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    NeoJJHunkHeaderCursor         = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    NeoJJDiffContext              = { bg = palette.bg1 },
    NeoJJDiffContextHighlight     = { bg = palette.bg2 },
    NeoJJDiffContextCursor        = { bg = palette.bg1 },
    NeoJJDiffAdditions            = { fg = palette.bg_green , ctermfg = 2 },
    NeoJJDiffAdd                  = { bg = palette.line_green, fg = palette.bg_green, ctermfg = 2 },
    NeoJJDiffAddHighlight         = { bg = palette.line_green, fg = palette.green, ctermfg = 2 },
    NeoJJDiffAddCursor            = { bg = palette.bg1, fg = palette.green, ctermfg = 2 },
    NeoJJDiffDeletions            = { fg = palette.bg_red, ctermfg = 1 },
    NeoJJDiffDelete               = { bg = palette.line_red, fg = palette.bg_red, ctermfg = 1 },
    NeoJJDiffDeleteHighlight      = { bg = palette.line_red, fg = palette.red, ctermfg = 1 },
    NeoJJDiffDeleteCursor         = { bg = palette.bg1, fg = palette.red, ctermfg = 1 },
    NeoJJPopupSectionTitle        = { link = "Function" },
    NeoJJPopupBranchName          = { link = "String" },
    NeoJJPopupBold                = { bold = palette.bold },
    NeoJJPopupSwitchKey           = { fg = palette.purple, ctermfg = 5 },
    NeoJJPopupSwitchEnabled       = { link = "SpecialChar" },
    NeoJJPopupSwitchDisabled      = { link = "NeoJJSubtleText" },
    NeoJJPopupOptionKey           = { fg = palette.purple, ctermfg = 5 },
    NeoJJPopupOptionEnabled       = { link = "SpecialChar" },
    NeoJJPopupOptionDisabled      = { link = "NeoJJSubtleText" },
    NeoJJPopupConfigKey           = { fg = palette.purple, ctermfg = 5 },
    NeoJJPopupConfigEnabled       = { link = "SpecialChar" },
    NeoJJPopupConfigDisabled      = { link = "NeoJJSubtleText" },
    NeoJJPopupActionKey           = { fg = palette.purple, ctermfg = 5 },
    NeoJJPopupActionDisabled      = { link = "NeoJJSubtleText" },
    NeoJJFilePath                 = { fg = palette.blue, italic = palette.italic, ctermfg = 3 },
    NeoJJCommitViewHeader         = { bg = palette.bg_cyan, fg = palette.bg0, ctermfg = 7 },
    NeoJJCommitViewDescription    = { link = "String" },
    NeoJJDiffHeader               = { bg = palette.bg3, fg = palette.blue, bold = palette.bold, ctermfg = 3 },
    NeoJJDiffHeaderHighlight      = { bg = palette.bg3, fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    NeoJJCommandText              = { link = "NeoJJSubtleText" },
    NeoJJCommandTime              = { link = "NeoJJSubtleText" },
    NeoJJCommandCodeNormal        = { link = "String" },
    NeoJJCommandCodeError         = { link = "Error" },
    NeoJJBranch                   = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    NeoJJBranchHead               = { fg = palette.blue, bold = palette.bold, underline = palette.underline, ctermfg = 4 },
    NeoJJRemote                   = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeoJJObjectId                 = { link = "NeoJJSubtleText" },
    NeoJJChangeId                 = { fg = palette.purple, bold = palette.bold, ctermfg = 5 },
    NeoJJConflict                 = { fg = palette.red, bold = palette.bold, ctermfg = 1 },
    NeoJJImmutable                = { fg = palette.grey, italic = palette.italic, ctermfg = 7 },
    NeoJJWorkingCopy              = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeoJJBookmark                 = { link = "NeoJJBranch" },
    NeoJJFold                     = { fg = "None", bg = "None" },
    NeoJJFoldColumn               = { fg = "None", bg = "None" },
    NeoJJWinSeparator             = { link = "WinSeparator" },
    NeoJJChangeModified           = { fg = palette.bg_blue, bold = palette.bold, italic = palette.italic, ctermfg = 4 },
    NeoJJChangeAdded              = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    NeoJJChangeDeleted            = { fg = palette.bg_red, bold = palette.bold, italic = palette.italic, ctermfg = 1 },
    NeoJJChangeRenamed            = { fg = palette.bg_purple, bold = palette.bold, italic = palette.italic, ctermfg = 5 },
    NeoJJChangeUpdated            = { fg = palette.bg_orange, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    NeoJJChangeCopied             = { fg = palette.bg_cyan, bold = palette.bold, italic = palette.italic, ctermfg = 6 },
    NeoJJChangeUnmerged           = { fg = palette.bg_yellow, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    NeoJJChangeNewFile            = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    NeoJJSectionHeader            = { fg = palette.bg_purple, bold = palette.bold, ctermfg = 5 },
    NeoJJSectionHeaderCount       = {},
    NeoJJRecentcommits            = { link = "NeoJJSectionHeader" },
    NeoJJTagName                  = { fg = palette.yellow, ctermfg = 3 },
    NeoJJTagDistance              = { fg = palette.cyan, ctermfg = 6 },
    NeoJJFloatHeader              = { bg = palette.bg0, bold = palette.bold, ctermfg = 5 },
    NeoJJFloatHeaderHighlight     = { bg = palette.bg2, fg = palette.cyan, bold = palette.bold, ctermfg = 5 },
    NeoJJActiveItem               = { bg = palette.bg_orange, fg = palette.bg0, bold = palette.bold, ctermfg = 5 },
  }

  for group, hl in pairs(hl_store) do
    if not is_set(group) then
      hl.default = true
      vim.api.nvim_set_hl(0, group, hl)
    end
  end
end

return M
