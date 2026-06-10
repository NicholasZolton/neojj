local util = require("neojj.lib.util")

local default_component_options = {
  foldable = false,
  folded = false,
}

---@class ComponentPosition
---@field row_start integer
---@field row_end integer
---@field col_start integer
---@field col_end integer

---Every field is optional: components declare only the options relevant to
---their line, and defaults are merged in at construction time.
---@class ComponentOptions
---@field line_hl string|nil
---@field highlight string|nil
---@field align_right integer|nil
---@field padding_left integer|nil
---@field tag string|nil
---@field foldable boolean|nil
---@field folded boolean|nil
---@field context boolean|nil
---@field interactive boolean|nil
---@field virtual_text string|nil
---@field section string|nil
---@field item table|nil
---@field id string|nil
---@field oid string|nil
---@field ref ParsedRef|nil
---@field yankable string|nil
---@field kind UiContextKind|nil Semantic kind of the line, resolved by Ui.resolve_context
---@field bookmarks string[]|nil Bookmark names on lines without an item (head/parent headers)
---@field commit_id string|nil Commit id on lines without an item (head/parent headers)
---@field on_open fun(fold, Ui)|nil
---@field hunk Hunk|nil
---@field filename string|nil
---@field value any

---@class Component
---@field position ComponentPosition
---@field parent Component
---@field children Component[]
---@field tag string|nil
---@field options ComponentOptions
---@field index number|nil
---@field value string|nil
---@field id string|nil
---@field highlight fun(hl_group:string): self
---@field line_hl fun(hl_group:string): self
---@field padding_left fun(string): self
---@field first integer|nil first line component appears rendered in buffer
---@field last integer|nil  last line component appears rendered in buffer
---@operator call: Component
local Component = {}

---@return integer, integer
function Component:row_range_abs()
  return self.position.row_start, self.position.row_end
end

function Component:get_padding_left(recurse)
  local padding_left = self.options.padding_left or 0
  local padding_left_text = type(padding_left) == "string" and padding_left or (" "):rep(padding_left)
  if recurse == false then
    return padding_left_text
  end
  return padding_left_text .. (self.parent and self.parent:get_padding_left() or "")
end

function Component:get_width()
  if self.tag == "text" then
    local width = string.len(self.value)
    -- local width = vim.fn.strdisplaywidth(self.value)
    if self.options.align_right then
      return width + (self.options.align_right - width)
    else
      return width
    end
  end

  if self.tag == "row" then
    local width = 0
    for i = 1, #self.children do
      width = width + self.children[i]:get_width()
    end
    return width
  end

  if self.tag == "col" then
    local width = 0
    for i = 1, #self.children do
      local c_width = self.children[i]:get_width()
      if c_width > width then
        width = c_width
      end
    end
    return width
  end

  error("UNIMPLEMENTED")
end

function Component:get_tag()
  if self.options.tag then
    return self.options.tag .. "<" .. self.tag .. ">"
  else
    return self.tag
  end
end

function Component:get_line_highlight()
  return self.options.line_hl or (self.parent and self.parent:get_line_highlight() or nil)
end

function Component:get_highlight()
  return self.options.highlight or (self.parent and self.parent:get_highlight() or nil)
end

function Component:append(c)
  table.insert(self.children, c)
  return self
end

---@param ui Ui
---@param depth integer
function Component:open_all_folds(ui, depth)
  assert(ui, "Pass in self.buffer.ui")

  if self.options.foldable then
    if self.options.on_open then
      self.options.on_open(self, ui)
    end

    self.options.folded = false
    depth = depth - 1
  end

  if self.children and depth > 0 then
    for _, child in ipairs(self.children) do
      child:open_all_folds(ui, depth)
    end
  end
end

---@param ui Ui
function Component:close_all_folds(ui)
  assert(ui, "Pass in self.buffer.ui")

  if self.options.foldable then
    self.options.folded = true
  end

  if self.children then
    for _, child in ipairs(self.children) do
      child:close_all_folds(ui)
    end
  end
end

---@param f fun(...): table
---@return Component
function Component.new(f)
  local instance = {}

  local mt = {
    __call = function(tbl, ...)
      local this = f(...)

      local options = vim.tbl_extend("force", default_component_options, tbl, this.options or {})
      this.options = options

      setmetatable(this, { __index = Component })

      return this
    end,
    __index = function(tbl, name)
      local value = rawget(Component, name)

      if value == nil then
        value = function(value)
          local options = util.deepcopy(tbl)
          options[name] = value
          return options
        end
      end

      return value
    end,
  }

  setmetatable(instance, mt)

  return instance
end

return Component
