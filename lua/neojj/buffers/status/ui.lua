local Ui = require("neojj.lib.ui")
local Component = require("neojj.lib.ui.component")
local util = require("neojj.lib.util")
local common = require("neojj.buffers.common")
local a = require("plenary.async")
local event = require("neojj.lib.event")

local col = Ui.col
local row = Ui.row
local text = Ui.text

local map = util.map

local EmptyLine = common.EmptyLine
local List = common.List
local DiffHunks = common.DiffHunks

local M = {}

local HINT = Component.new(function(props)
  ---@return table<string, string[]>
  local function reversed_lookup(tbl)
    local result = {}
    for k, v in pairs(tbl) do
      if v then
        local current = result[v]
        if current then
          table.insert(current, k)
        else
          result[v] = { k }
        end
      end
    end

    return result
  end

  local reversed_status_map = reversed_lookup(props.config.mappings.status)
  local reversed_popup_map = reversed_lookup(props.config.mappings.popup)

  local entry = function(name, hint)
    local keys = reversed_status_map[name] or reversed_popup_map[name]
    local key_hint

    if keys and #keys > 0 then
      key_hint = table.concat(keys, " ")
    else
      key_hint = "<unmapped>"
    end

    return row {
      text.highlight("NeoJJPopupActionKey")(key_hint),
      text(" "),
      text(hint),
    }
  end

  return row {
    text.highlight("NeoJJSubtleText")("Hint: "),
    entry("Toggle", "toggle"),
    text.highlight("NeoJJSubtleText")(" | "),
    entry("Discard", "discard"),
    text.highlight("NeoJJSubtleText")(" | "),
    entry("CommitPopup", "change"),
    text.highlight("NeoJJSubtleText")(" | "),
    entry("RebasePopup", "rebase"),
    text.highlight("NeoJJSubtleText")(" | "),
    entry("BookmarkPopup", "bookmark"),
    text.highlight("NeoJJSubtleText")(" | "),
    entry("HelpPopup", "help"),
  }
end)

--- Head/Parent section showing current change and its parent
local JJHead = Component.new(function(props)
  local change_id = props.change_id or ""
  local commit_id = props.commit_id or ""
  local short_change = change_id:sub(1, 8)
  local short_commit = commit_id:sub(1, 8)

  local bookmark_parts = {}
  if props.bookmarks and #props.bookmarks > 0 then
    for _, bm in ipairs(props.bookmarks) do
      table.insert(bookmark_parts, text(" "))
      table.insert(bookmark_parts, text.highlight("NeoJJBranchHead")(bm))
    end
  end

  local status_parts = {}
  if props.empty then
    table.insert(status_parts, "empty")
  end
  if props.conflict then
    table.insert(status_parts, "conflict")
  end
  local status_text = #status_parts > 0 and " (" .. table.concat(status_parts, ", ") .. ")" or ""

  local header_parts = {
    text.highlight("NeoJJStatusHEAD")(util.pad_right(props.name .. ": ", props.HEAD_padding or 10)),
    text.highlight("NeoJJBranch")(props.symbol .. " "),
    text.highlight("NeoJJChangeId")(short_change),
    text(" "),
    text.highlight("NeoJJObjectId")(short_commit),
  }
  vim.list_extend(header_parts, bookmark_parts)
  table.insert(header_parts, text.highlight(props.conflict and "NeoJJConflict" or "NeoJJSubtleText")(status_text))

  return col({
    row(header_parts),
    row {
      text("  "),
      text(props.description ~= "" and vim.split(props.description, "\n")[1] or "(no description)"),
    },
  }, { yankable = change_id })
end)

local SectionTitle = Component.new(function(props)
  return { text.highlight(props.highlight or "NeoJJSectionHeader")(props.title) }
end)

local Section = Component.new(function(props)
  local count
  if props.count then
    count = { text(" ("), text.highlight("NeoJJSectionHeaderCount")(#props.items), text(")") }
  end

  return col.tag("Section")({
    row(util.merge(props.title, count or {})),
    col(map(props.items, props.render)),
    EmptyLine(),
  }, {
    foldable = true,
    folded = props.folded,
    section = props.name,
    id = props.name,
  })
end)

local SectionItemFile = function(section, config)
  return Component.new(function(item)
    local load_diff = function(item)
      ---@param this Component
      ---@param ui Ui
      ---@param prefix string|nil
      return a.void(function(this, ui, prefix)
        this.options.on_open = nil
        this.options.folded = false

        local row, _ = this:row_range_abs()
        row = row + 1 -- Filename row

        local diff = item.diff
        for _, hunk in ipairs(diff.hunks) do
          hunk.first = row
          hunk.last = row + hunk.length
          row = hunk.last + 1

          -- Set fold state when called from ui:update()
          if prefix then
            local key = ("%s--%s"):format(prefix, hunk.hash)
            if ui._node_fold_state and ui._node_fold_state[key] then
              hunk._folded = ui._node_fold_state[key].folded
            end
          end
        end

        ui.buf:with_locked_viewport(function()
          this:append(DiffHunks(diff))
          ui:update()
        end)

        event.send("DiffLoaded", {
          item = {
            absolute_path = item.absolute_path,
            relative_path = item.escaped_path,
            row_start = item.first,
            row_end = item.last,
            mode = item.mode,
          },
          diff = {
            kind = diff.kind,
            lines = diff.lines,
            hunks = util.map(diff.hunks, function(hunk)
              local original_lines = util.filter_map(hunk.lines, function(line)
                if not (vim.startswith(line, "+") or vim.startswith(line, "-")) then
                  return line
                end
              end)

              local modified_lines = util.map(hunk.lines, function(line)
                return line:gsub("^[+-]", " ")
              end)

              return {
                lines = hunk.lines,
                original_lines = original_lines,
                modified_lines = modified_lines,
                row_start = hunk.first,
                row_end = hunk.last,
                header = hunk.line,
              }
            end),
          },
        })
      end)
    end

    local mode = config.status.mode_text[item.mode]
    local mode_text
    if mode == "" then
      mode_text = ""
    elseif mode and config.status.mode_padding > 0 then
      mode_text = util.pad_right(
        mode,
        util.max_length(vim.tbl_values(config.status.mode_text)) + config.status.mode_padding
      )
    else
      mode_text = item.mode .. " "
    end

    local name = item.original_name and ("%s -> %s"):format(item.original_name, item.name) or item.name
    local highlight = "NeoJJFileMode"

    return col.tag("Item")({
      row {
        text.highlight(highlight)(mode_text),
        text(name),
      },
    }, {
      foldable = true,
      folded = true,
      on_open = load_diff(item),
      context = true,
      id = ("%s--%s"):format(section, item.name),
      yankable = item.name,
      filename = item.name,
      item = item,
    })
  end)
end

local SectionItemChange = Component.new(function(item)
  local change_id = (item.change_id or ""):sub(1, 8)
  local commit_id = (item.commit_id or ""):sub(1, 8)

  local bookmark_parts = {}
  if item.bookmarks and #item.bookmarks > 0 then
    for _, bm in ipairs(item.bookmarks) do
      table.insert(bookmark_parts, text(" "))
      table.insert(bookmark_parts, text.highlight("NeoJJBranchHead")(bm))
    end
  end

  local status_parts = {}
  if item.empty then
    table.insert(status_parts, "empty")
  end
  if item.conflict then
    table.insert(status_parts, "conflict")
  end
  local status_suffix = #status_parts > 0 and " (" .. table.concat(status_parts, ", ") .. ")" or ""

  local parts = {
    text.highlight("NeoJJChangeId")(change_id),
    text(" "),
    text.highlight("NeoJJObjectId")(commit_id),
  }
  vim.list_extend(parts, bookmark_parts)
  table.insert(parts, text(" "))
  table.insert(parts, text(item.description and vim.split(item.description, "\n")[1] or "(no description)"))
  table.insert(parts, text.highlight(item.conflict and "NeoJJConflict" or "NeoJJSubtleText")(status_suffix))

  return row(parts, {
    yankable = item.change_id,
    item = item,
  })
end)

local SectionItemBookmark = Component.new(function(item)
  local label = item.name
  local highlight = "NeoJJBranch"
  if item.deleted then
    highlight = "NeoJJSubtleText"
  elseif item.remote and item.remote ~= "" then
    label = item.name .. "@" .. item.remote
    highlight = "NeoJJRemote"
  end

  local parts = {
    text.highlight(highlight)(label),
  }

  if not item.deleted then
    table.insert(parts, text(" "))
    table.insert(parts, text.highlight("NeoJJChangeId")((item.change_id or ""):sub(1, 8)))
    table.insert(parts, text(" "))
    table.insert(parts, text(item.description and vim.split(item.description, "\n")[1] or "(no description)"))
  else
    table.insert(parts, text.highlight("NeoJJSubtleText")(" (deleted)"))
  end

  return row(parts, {
    yankable = item.name,
    item = item,
  })
end)

local SectionItemConflict = Component.new(function(item)
  return row({
    text.highlight("NeoJJGraphRed")("C "),
    text(item.name),
  }, {
    yankable = item.name,
    item = item,
  })
end)

function M.Status(state, config)
  -- stylua: ignore start
  local show_hint = not config.disable_hint

  local show_files = state.files and #state.files.items > 0

  local show_conflicts = state.conflicts and #state.conflicts.items > 0

  local show_recent = state.recent and #state.recent.items > 0

  local bookmarks_hidden = config.sections and config.sections.bookmarks and config.sections.bookmarks.hidden
  local show_bookmarks = not bookmarks_hidden and state.bookmarks and #state.bookmarks.items > 0

  local HEAD_padding = config.status and config.status.HEAD_padding or 10

  return {
    List {
      items = {
        show_hint and HINT { config = config },
        show_hint and EmptyLine(),
        col.tag("Section")({
          JJHead {
            name = "Change",
            symbol = "@",
            change_id = state.head.change_id,
            commit_id = state.head.commit_id,
            description = state.head.description,
            bookmarks = state.head.bookmarks,
            empty = state.head.empty,
            conflict = state.head.conflict,
            HEAD_padding = HEAD_padding,
          },
          EmptyLine(),
          JJHead {
            name = "Parent",
            symbol = "@-",
            change_id = state.parent.change_id,
            commit_id = state.parent.commit_id,
            description = state.parent.description,
            bookmarks = state.parent.bookmarks,
            empty = false,
            conflict = false,
            HEAD_padding = HEAD_padding,
          },
        }, { foldable = true, folded = config.status and config.status.HEAD_folded }),
        EmptyLine(),
        show_conflicts and Section {
          title = SectionTitle { title = "Conflicts", highlight = "NeoJJSectionConflicts" },
          count = true,
          render = SectionItemConflict,
          items = state.conflicts.items,
          folded = false,
          name = "conflicts",
        },
        show_files and Section {
          title = SectionTitle { title = "Modified files", highlight = "NeoJJSectionFiles" },
          count = true,
          render = SectionItemFile("files", config),
          items = state.files.items,
          folded = false,
          name = "files",
        },
        show_recent and Section {
          title = SectionTitle { title = "Recent Changes", highlight = "NeoJJSectionRecent" },
          count = false,
          render = SectionItemChange,
          items = state.recent.items,
          folded = config.sections and config.sections.recent and config.sections.recent.folded,
          name = "recent",
        },
        show_bookmarks and Section {
          title = SectionTitle { title = "Bookmarks", highlight = "NeoJJSectionBookmarks" },
          count = true,
          render = SectionItemBookmark,
          items = state.bookmarks.items,
          folded = config.sections and config.sections.bookmarks and config.sections.bookmarks.folded,
          name = "bookmarks",
        },
      },
    },
  }
end

-- stylua: ignore end

return M
