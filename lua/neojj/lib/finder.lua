local config = require("neojj.config")
local a = require("plenary.async")

local function refocus_status_buffer()
  local status = require("neojj.buffers.status")
  if status.instance() then
    status.instance():focus()
    status.instance():dispatch_refresh(nil, "finder.refocus")
  end
end

local copy_selection = function()
  local selection = require("telescope.actions.state").get_selected_entry()
  if selection ~= nil then
    vim.cmd.let(("@+=%q"):format(selection[1]))
  end
end

local function telescope_mappings(on_select, allow_multi, refocus_status)
  local action_state = require("telescope.actions.state")
  local actions = require("telescope.actions")

  local function close_action(prompt_bufnr)
    actions.close(prompt_bufnr)

    if refocus_status then
      refocus_status_buffer()
    end
  end

  --- Lift the picker select action to a item select action
  local function select_action(prompt_bufnr)
    local selection = {}

    local picker = action_state.get_current_picker(prompt_bufnr)
    if #picker:get_multi_selection() > 0 then
      for _, item in ipairs(picker:get_multi_selection()) do
        table.insert(selection, item[1])
      end
    elseif action_state.get_selected_entry() ~= nil then
      local entry = action_state.get_selected_entry()[1]
      local prompt = picker:_get_prompt()

      local navigate_up_level = entry == ".." and #prompt > 0
      local input_git_refspec = prompt:match("%^")
        or prompt:match("~")
        or prompt:match("@")
        or prompt:match(":")

      if navigate_up_level or input_git_refspec then
        table.insert(selection, prompt)
      else
        table.insert(selection, entry)
      end
    else
      table.insert(selection, picker:_get_prompt())
    end

    if not selection[1] or selection[1] == "" then
      return
    end

    close_action(prompt_bufnr)

    if allow_multi then
      on_select(selection)
    else
      on_select(selection[1])
    end
  end

  local function close(...)
    -- Make sure to notify the caller that we aborted to avoid hanging on the async task forever
    on_select(nil)
    close_action(...)
  end

  local function completion_action(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    -- selene: allow(empty_if)
    if #picker:get_multi_selection() > 0 then
      -- Don't autocomplete with multiple selection
    elseif action_state.get_selected_entry() ~= nil then
      picker:set_prompt(action_state.get_selected_entry()[1])
    end
  end

  return function(_, map)
    local commands = {
      ["Select"] = select_action,
      ["Close"] = close,
      ["InsertCompletion"] = completion_action,
      ["Next"] = actions.move_selection_next,
      ["Previous"] = actions.move_selection_previous,
      ["CopySelection"] = copy_selection,
      ["NOP"] = actions.nop,
      ["MultiselectToggleNext"] = actions.toggle_selection + actions.move_selection_worse,
      ["MultiselectTogglePrevious"] = actions.toggle_selection + actions.move_selection_better,
      ["MultiselectToggle"] = actions.toggle_selection,
    }

    -- Telescope HEAD has mouse click support, but not the latest tag. Need to check if the user has
    -- support for mouse click, while avoiding the error that the metatable raises.
    -- stylua: ignore
    if pcall(function() return actions.mouse_click and true end) then
      commands.ScrollWheelDown = actions.move_selection_next
      commands.ScrollWheelUp = actions.move_selection_previous
      commands.MouseClick = actions.mouse_click
    end

    for mapping, command in pairs(config.values.mappings.finder) do
      if command and command:match("^Multiselect") then
        if allow_multi then
          map({ "i" }, mapping, commands[command])
        end
      elseif command then
        map({ "i" }, mapping, commands[command])
      end
    end

    return false
  end
end

--- Utility function to map actions
---@param on_select fun(item: any|nil)
---@param allow_multi boolean
---@param refocus_status boolean
local function fzf_actions(on_select, allow_multi, refocus_status)
  local function refresh()
    if refocus_status then
      refocus_status_buffer()
    end
  end

  local function close_action()
    on_select(nil)
    refresh()
  end

  return {
    ["default"] = function(selected)
      if allow_multi then
        on_select(selected)
      else
        on_select(selected[1])
      end
      refresh()
    end,
    ["esc"] = close_action,
    ["ctrl-c"] = close_action,
    ["ctrl-q"] = close_action,
  }
end

--- Extract plain text strings from entries (handles both string and table entries)
---@param entries any[]
---@return string[]
local function entries_to_strings(entries)
  local result = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "table" then
      table.insert(result, entry.text)
    else
      table.insert(result, entry)
    end
  end
  return result
end

---Convert entries to snack picker items
---@param entries any[]
---@return any[]
local function entries_to_snack_items(entries)
  local items = {}
  for idx, entry in ipairs(entries) do
    local text = type(entry) == "table" and entry.text or entry
    local prefix_len = type(entry) == "table" and entry.prefix_len or nil
    table.insert(items, { idx = idx, score = 0, text = text, prefix_len = prefix_len })
  end
  return items
end

--- Utility function to map actions
---@param on_select fun(item: any|nil)
---@param allow_multi boolean
---@param refocus_status boolean
local function snacks_confirm(on_select, allow_multi, refocus_status)
  local completed = false
  local function complete(selection)
    if completed then
      return
    end
    on_select(selection)
    completed = true
    if refocus_status then
      refocus_status_buffer()
    end
  end
  local function confirm(picker, item)
    local selection = {}
    local picker_selected = picker:selected { fallback = true }

    if #picker_selected == 0 then
      local prompt = picker:filter().pattern
      table.insert(selection, prompt)
    elseif #picker_selected > 1 then
      for _, item in ipairs(picker_selected) do
        table.insert(selection, item.text)
      end
    else
      local entry = item.text
      local prompt = picker:filter().pattern

      local navigate_up_level = entry == ".." and #prompt > 0
      local input_git_refspec = prompt:match("%^")
        or prompt:match("~")
        or prompt:match("@")
        or prompt:match(":")

      table.insert(selection, (navigate_up_level or input_git_refspec) and prompt or entry)
    end

    if selection and selection[1] and selection[1] ~= "" then
      complete(allow_multi and selection or selection[1])
      picker:close()
    end
  end

  local function on_close()
    complete(nil)
  end

  return confirm, on_close
end

---Completes the finder when MiniPick confirms or cancels a selection.
---@param on_select fun(item: any|nil)
---@param refocus_status boolean
---@return function choose, function on_stop
local function mini_pick_choose(on_select, refocus_status)
  local completed = false

  local function complete(selection)
    if completed then
      return
    end
    completed = true
    on_select(selection)
    if refocus_status then
      refocus_status_buffer()
    end
  end

  return function(item)
    complete(item)
  end, function()
    complete(nil)
  end
end

--- Utility function to map finder opts to fzf
---@param opts FinderOpts
---@return table
local function fzf_opts(opts)
  local fzf_opts = {}

  -- Allow multi by default
  if opts.allow_multi then
    fzf_opts["--multi"] = ""
  else
    fzf_opts["--no-multi"] = ""
  end

  if opts.layout_config.prompt_position ~= "top" then
    fzf_opts["--layout"] = "reverse-list"
  end

  if opts.border then
    fzf_opts["--border"] = "rounded"
  else
    fzf_opts["--border"] = "none"
  end

  return fzf_opts
end

---@return FinderOpts
local function default_opts()
  return {
    layout_config = {
      height = 0.3,
      prompt_position = "top",
      preview_cutoff = vim.fn.winwidth(0),
    },
    refocus_status = true,
    allow_multi = false,
    border = false,
    prompt_prefix = "select",
    previewer = false,
    cache_picker = false,
    layout_strategy = "bottom_pane",
    sorting_strategy = "ascending",
    theme = "ivy",
  }
end

---@class FinderOpts
---@field layout_config table
---@field allow_multi boolean
---@field border boolean
---@field prompt_prefix string
---@field previewer boolean
---@field layout_strategy string
---@field sorting_strategy string
---@field theme string

---@class Finder
---@field opts table
---@field entries table
---@field mappings function|nil
local Finder = {}
Finder.__index = Finder

---@param opts FinderOpts
---@return Finder
function Finder:new(opts)
  local this = {
    opts = vim.tbl_deep_extend("keep", opts, default_opts()),
    entries = {},
    select_action = nil,
  }

  setmetatable(this, self)

  return this
end

---Adds entries to internal table
---@param entries table
---@return Finder
function Finder:add_entries(entries)
  for _, entry in ipairs(entries) do
    table.insert(self.entries, entry)
  end
  return self
end

---Engages finder and invokes `on_select` with the item or items, or nil if aborted
---@param on_select fun(item: any|nil)
function Finder:find(on_select)
  if config.check_integration("telescope") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")

    self.opts.prompt_prefix = string.format(" %s > ", self.opts.prompt_prefix)

    local default_sorter
    local native_sorter = function()
      local fzf_extension = require("telescope").extensions.fzf
      if fzf_extension then
        default_sorter = fzf_extension.native_fzf_sorter()
      end
    end

    if not pcall(native_sorter) then
      default_sorter = sorters.get_generic_fuzzy_sorter()
    end

    pickers
      .new(self.opts, {
        finder = finders.new_table { results = entries_to_strings(self.entries) },
        sorter = config.values.telescope_sorter() or default_sorter,
        attach_mappings = telescope_mappings(on_select, self.opts.allow_multi, self.opts.refocus_status),
      })
      :find()
  elseif config.check_integration("fzf_lua") then
    local fzf_lua = require("fzf-lua")
    fzf_lua.fzf_exec(entries_to_strings(self.entries), {
      prompt = string.format("%s> ", self.opts.prompt_prefix),
      fzf_opts = fzf_opts(self.opts),
      winopts = {
        height = self.opts.layout_config.height,
        border = self.opts.border,
        preview = { border = self.opts.border },
      },
      actions = fzf_actions(on_select, self.opts.allow_multi, self.opts.refocus_status),
    })
  elseif config.check_integration("mini_pick") then
    local mini_pick = require("mini.pick")
    local choose, on_stop = mini_pick_choose(on_select, self.opts.refocus_status)

    -- Build a lookup from display text -> prefix_len for bold highlighting
    local prefix_lookup = {}
    for _, entry in ipairs(self.entries) do
      if type(entry) == "table" and entry.prefix_len then
        prefix_lookup[entry.text] = entry.prefix_len
      end
    end

    local string_items = entries_to_strings(self.entries)
    local has_prefixes = next(prefix_lookup) ~= nil

    local show = nil
    if has_prefixes then
      local ns = vim.api.nvim_create_namespace("neojj_picker_prefix")
      show = function(buf_id, items_to_show, query, opts)
        mini_pick.default_show(buf_id, items_to_show, query, opts)
        vim.api.nvim_buf_clear_namespace(buf_id, ns, 0, -1)
        for i, item in ipairs(items_to_show) do
          local item_text = type(item) == "string" and item or tostring(item)
          local plen = prefix_lookup[item_text]
          if plen and plen > 0 then
            -- Bold prefix
            vim.api.nvim_buf_set_extmark(buf_id, ns, i - 1, 0, {
              end_col = plen,
              hl_group = "NeojjChangeIdPrefix",
              hl_mode = "combine",
              priority = 210,
            })
            -- Dim rest of change_id (up to first space)
            local rest_end = item_text:find(" ") or (#item_text + 1)
            if rest_end > plen + 1 then
              vim.api.nvim_buf_set_extmark(buf_id, ns, i - 1, plen, {
                end_col = rest_end - 1,
                hl_group = "NeojjChangeIdRest",
                hl_mode = "combine",
                priority = 210,
              })
            end
          end
        end
      end
    end

    local group = vim.api.nvim_create_augroup("NeojjMiniPickStop", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniPickStop",
      once = true,
      group = group,
      callback = function()
        vim.api.nvim_clear_autocmds { group = group }
        on_stop()
      end,
    })

    mini_pick.start {
      source = {
        items = string_items,
        choose = choose,
        show = show or nil,
      },
    }
  elseif config.check_integration("snacks") then
    local snacks_picker = require("snacks.picker")
    local confirm, on_close = snacks_confirm(on_select, self.opts.allow_multi, self.opts.refocus_status)
    local snack_items = entries_to_snack_items(self.entries)

    -- Check if any items have prefix_len for change ID highlighting
    local has_prefixes = false
    for _, item in ipairs(snack_items) do
      if item.prefix_len then
        has_prefixes = true
        break
      end
    end

    ---@type string|fun(item: table): table
    local format_fn = "text"
    if has_prefixes then
      format_fn = function(item)
        local ret = {}
        local item_text = item.text or ""
        local plen = item.prefix_len
        if plen and plen > 0 and plen < #item_text then
          local space_pos = item_text:find(" ") or (#item_text + 1)
          ret[#ret + 1] = { item_text:sub(1, plen), "NeojjChangeIdPrefix" }
          if space_pos > plen + 1 then
            ret[#ret + 1] = { item_text:sub(plen + 1, space_pos - 1), "NeojjChangeIdRest" }
          end
          ret[#ret + 1] = { item_text:sub(space_pos) }
        else
          ret[#ret + 1] = { item_text }
        end
        return ret
      end
    end

    snacks_picker.pick(nil, {
      title = "Neojj",
      prompt = string.format("%s > ", self.opts.prompt_prefix),
      items = snack_items,
      format = format_fn,
      layout = {
        preset = self.opts.theme,
        preview = self.opts.previewer,
        height = self.opts.layout_config.height,
        border = self.opts.border and "rounded" or "none",
      },
      confirm = confirm,
      on_close = on_close,
    })
  else
    vim.ui.select(entries_to_strings(self.entries), {
      prompt = string.format("%s: ", self.opts.prompt_prefix),
      format_item = function(entry)
        return entry
      end,
    }, function(item)
      vim.schedule(function()
        on_select(self.opts.allow_multi and { item } or item)

        if self.opts.refocus_status then
          refocus_status_buffer()
        end
      end)
    end)
  end
end

---@type async fun(self: Finder): any|nil
--- Asynchronously prompt the user for the selection, and return the selected item or nil if aborted.
Finder.find_async = a.wrap(Finder.find, 2)

---Builds Finder instance
---@param opts table|nil
---@return Finder
function Finder.create(opts)
  return Finder:new(opts or {})
end

--- Example usage
function Finder.test()
  a.run(function()
    local f = Finder:create()
    f:add_entries { "a", "b", "c" }

    local item = f:find_async()

    if item then
      print("Got item: ", vim.inspect(item))
    else
      print("Aborted")
    end
  end)
end

return Finder
