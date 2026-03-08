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

---@class NeojjColorPalette
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
---@param config NeojjConfig
---@return NeojjColorPalette
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

---@param config NeojjConfig
function M.setup(config)
  local palette = make_palette(config)

  -- stylua: ignore
  hl_store = {
    NeojjGraphAuthor              = { fg = palette.orange , ctermfg = 3 },
    NeojjGraphRed                 = { fg = palette.red, ctermfg = 1 },
    NeojjGraphWhite               = { fg = palette.white, ctermfg =  7 },
    NeojjGraphYellow              = { fg = palette.yellow, ctermfg = 3 },
    NeojjGraphGreen               = { fg = palette.green, ctermfg = 2 },
    NeojjGraphCyan                = { fg = palette.cyan, ctermfg = 6 },
    NeojjGraphBlue                = { fg = palette.blue, ctermfg = 4 },
    NeojjGraphPurple              = { fg = palette.purple, ctermfg = 5 },
    NeojjGraphGray                = { fg = palette.grey, ctermfg = 7 },
    NeojjGraphOrange              = { fg = palette.orange, ctermfg = 3 },
    NeojjGraphBoldOrange          = { fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    NeojjGraphBoldRed             = { fg = palette.red, bold = palette.bold, ctermfg = 1 },
    NeojjGraphBoldWhite           = { fg = palette.white, bold = palette.bold, ctermfg = 7 },
    NeojjGraphBoldYellow          = { fg = palette.yellow, bold = palette.bold, ctermfg = 3 },
    NeojjGraphBoldGreen           = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeojjGraphBoldCyan            = { fg = palette.cyan, bold = palette.bold, ctermfg = 6 },
    NeojjGraphBoldBlue            = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    NeojjGraphBoldPurple          = { fg = palette.purple, bold = palette.bold, ctermfg = 5 },
    NeojjGraphBoldGray            = { fg = palette.grey, bold = palette.bold, ctermfg = 7 },
    NeojjSubtleText               = { link = "Comment" },
    NeojjSignatureGood            = { link = "NeojjGraphGreen" },
    NeojjSignatureBad             = { link = "NeojjGraphBoldRed" },
    NeojjSignatureMissing         = { link = "NeojjGraphPurple" },
    NeojjSignatureNone            = { link = "NeojjSubtleText" },
    NeojjSignatureGoodUnknown     = { link = "NeojjGraphBlue" },
    NeojjSignatureGoodExpired     = { link = "NeojjGraphOrange" },
    NeojjSignatureGoodExpiredKey  = { link = "NeojjGraphYellow" },
    NeojjSignatureGoodRevokedKey  = { link = "NeojjGraphRed" },
    NeojjNormal                   = { link = "Normal" },
    NeojjNormalFloat              = { link = "NeojjNormal" },
    NeojjFloatBorder              = { link = "NeojjNormalFloat" },
    NeojjSignColumn               = { fg = "None", bg = "None" },
    NeojjCursorLine               = { link = "CursorLine" },
    NeojjCursorLineNr             = { link = "CursorLineNr" },
    NeojjHunkMergeHeader          = { fg = palette.bg2, bg = palette.grey, bold = palette.bold, ctermfg = 4 },
    NeojjHunkMergeHeaderHighlight = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    NeojjHunkMergeHeaderCursor    = { fg = palette.bg0, bg = palette.bg_cyan, bold = palette.bold, ctermfg = 4 },
    NeojjHunkHeader               = { fg = palette.bg0, bg = palette.grey, bold = palette.bold, ctermfg = 3 },
    NeojjHunkHeaderHighlight      = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    NeojjHunkHeaderCursor         = { fg = palette.bg0, bg = palette.md_purple, bold = palette.bold, ctermfg = 3 },
    NeojjDiffContext              = { bg = palette.bg1 },
    NeojjDiffContextHighlight     = { bg = palette.bg2 },
    NeojjDiffContextCursor        = { bg = palette.bg1 },
    NeojjDiffAdditions            = { fg = palette.bg_green , ctermfg = 2 },
    NeojjDiffAdd                  = { bg = palette.line_green, fg = palette.bg_green, ctermfg = 2 },
    NeojjDiffAddHighlight         = { bg = palette.line_green, fg = palette.green, ctermfg = 2 },
    NeojjDiffAddCursor            = { bg = palette.bg1, fg = palette.green, ctermfg = 2 },
    NeojjDiffDeletions            = { fg = palette.bg_red, ctermfg = 1 },
    NeojjDiffDelete               = { bg = palette.line_red, fg = palette.bg_red, ctermfg = 1 },
    NeojjDiffDeleteHighlight      = { bg = palette.line_red, fg = palette.red, ctermfg = 1 },
    NeojjDiffDeleteCursor         = { bg = palette.bg1, fg = palette.red, ctermfg = 1 },
    NeojjPopupSectionTitle        = { link = "Function" },
    NeojjPopupBranchName          = { link = "String" },
    NeojjPopupBold                = { bold = palette.bold },
    NeojjPopupSwitchKey           = { fg = palette.purple, ctermfg = 5 },
    NeojjPopupSwitchEnabled       = { link = "SpecialChar" },
    NeojjPopupSwitchDisabled      = { link = "NeojjSubtleText" },
    NeojjPopupOptionKey           = { fg = palette.purple, ctermfg = 5 },
    NeojjPopupOptionEnabled       = { link = "SpecialChar" },
    NeojjPopupOptionDisabled      = { link = "NeojjSubtleText" },
    NeojjPopupConfigKey           = { fg = palette.purple, ctermfg = 5 },
    NeojjPopupConfigEnabled       = { link = "SpecialChar" },
    NeojjPopupConfigDisabled      = { link = "NeojjSubtleText" },
    NeojjPopupActionKey           = { fg = palette.purple, ctermfg = 5 },
    NeojjPopupActionDisabled      = { link = "NeojjSubtleText" },
    NeojjFilePath                 = { fg = palette.blue, italic = palette.italic, ctermfg = 3 },
    NeojjCommitViewHeader         = { bg = palette.bg_cyan, fg = palette.bg0, ctermfg = 7 },
    NeojjCommitViewDescription    = { link = "String" },
    NeojjDiffHeader               = { bg = palette.bg3, fg = palette.blue, bold = palette.bold, ctermfg = 3 },
    NeojjDiffHeaderHighlight      = { bg = palette.bg3, fg = palette.orange, bold = palette.bold, ctermfg = 3 },
    NeojjCommandText              = { link = "NeojjSubtleText" },
    NeojjCommandTime              = { link = "NeojjSubtleText" },
    NeojjCommandCodeNormal        = { link = "String" },
    NeojjCommandCodeError         = { link = "Error" },
    NeojjBranch                   = { fg = palette.blue, bold = palette.bold, ctermfg = 4 },
    NeojjBranchHead               = { fg = palette.blue, bold = palette.bold, underline = palette.underline, ctermfg = 4 },
    NeojjRemote                   = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeojjObjectId                 = { fg = palette.bg_cyan, ctermfg = 7 },
    NeojjChangeId                 = { fg = palette.bg_purple, ctermfg = 6 },
    NeojjConflict                 = { fg = "#f0c674", bold = true, ctermfg = 3 },
    NeojjImmutable                = { fg = palette.grey, italic = palette.italic, ctermfg = 7 },
    NeojjWorkingCopy              = { fg = palette.green, bold = palette.bold, ctermfg = 2 },
    NeojjBookmark                 = { link = "NeojjBranch" },
    NeojjFold                     = { fg = "None", bg = "None" },
    NeojjFoldColumn               = { fg = "None", bg = "None" },
    NeojjWinSeparator             = { link = "WinSeparator" },
    NeojjChangeModified           = { fg = palette.bg_blue, bold = palette.bold, italic = palette.italic, ctermfg = 4 },
    NeojjChangeAdded              = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    NeojjChangeDeleted            = { fg = palette.bg_red, bold = palette.bold, italic = palette.italic, ctermfg = 1 },
    NeojjChangeRenamed            = { fg = palette.bg_purple, bold = palette.bold, italic = palette.italic, ctermfg = 5 },
    NeojjChangeUpdated            = { fg = palette.bg_orange, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    NeojjChangeCopied             = { fg = palette.bg_cyan, bold = palette.bold, italic = palette.italic, ctermfg = 6 },
    NeojjChangeUnmerged           = { fg = palette.bg_yellow, bold = palette.bold, italic = palette.italic, ctermfg = 3 },
    NeojjChangeNewFile            = { fg = palette.bg_green, bold = palette.bold, italic = palette.italic, ctermfg = 2 },
    NeojjSectionHeader            = { fg = palette.md_purple, bold = palette.bold, ctermfg = 5 },
    NeojjSectionHeaderCount       = {},
    NeojjRecentcommits            = { link = "NeojjSectionHeader" },
    NeojjTagName                  = { fg = palette.yellow, ctermfg = 3 },
    NeojjTagDistance              = { fg = palette.cyan, ctermfg = 6 },
    NeojjFloatHeader              = { bg = palette.bg0, bold = palette.bold, ctermfg = 5 },
    NeojjFloatHeaderHighlight     = { bg = palette.bg2, fg = palette.cyan, bold = palette.bold, ctermfg = 5 },
    NeojjActiveItem               = { bg = palette.bg_orange, fg = palette.bg0, bold = palette.bold, ctermfg = 5 },
    -- Status buffer section headers (customizable separately)
    NeojjSectionConflicts         = { link = "NeojjGraphRed" },
    NeojjSectionFiles             = { link = "NeojjSectionHeader" },
    NeojjSectionRecent            = { link = "NeojjSectionHeader" },
    NeojjSectionBookmarks         = { link = "NeojjSectionHeader" },
    -- File mode text in Modified files section
    NeojjFileMode                 = { link = "NeojjBranch" },
  }

  for group, hl in pairs(hl_store) do
    if not is_set(group) then
      hl.default = true
      vim.api.nvim_set_hl(0, group, hl)
    end
  end
end

return M
