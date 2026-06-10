local Ui = require("neojj.lib.ui")
local Component = require("neojj.lib.ui.component")
local util = require("neojj.lib.util")
local jj = require("neojj.lib.jj")

local text = Ui.text
local col = Ui.col
local row = Ui.row
local map = util.map
local flat_map = util.flat_map
local filter = util.filter
local intersperse = util.intersperse

local M = {}

M.EmptyLine = Component.new(function()
  return col { row { text("") } }
end)

M.Diff = Component.new(function(diff)
  return col.tag("Diff")({
    text(string.format("%s %s", diff.kind, diff.file), { line_hl = "NeojjDiffHeader" }),
    M.DiffHunks(diff),
  }, { foldable = true, folded = false, context = true })
end)

-- Use vim iter api?
M.DiffHunks = Component.new(function(diff)
  local hunk_props = vim
    .iter(diff.hunks)
    :map(function(hunk)
      hunk.content = vim.iter(diff.lines):slice(hunk.diff_from + 1, hunk.diff_to):totable()

      return {
        header = diff.lines[hunk.diff_from],
        content = hunk.content,
        hunk = hunk,
        folded = hunk._folded,
      }
    end)
    :totable()

  return col.tag("DiffContent") {
    col.tag("DiffInfo")(map(diff.info, text)),
    col.tag("HunkList")(map(hunk_props, M.Hunk)),
  }
end)

local diff_add_start = "+"
local diff_add_start_2 = " +"
local diff_delete_start = "-"
local diff_delete_start_2 = " -"

local HunkLine = Component.new(function(line)
  local line_hl

  if vim.b.neojj_disable_hunk_highlight == true then
    return text(line)
  end

  local first_char = string.sub(line, 1, 1)
  local first_chars = string.sub(line, 1, 2)

  -- Check if there are active conflicts (jj stores conflicts in commits)
  local has_conflicts = false
  local ok, repo = pcall(function()
    return jj.repo
  end)
  if ok and repo and repo.state and repo.state.conflicts then
    has_conflicts = #repo.state.conflicts.items > 0
  end

  if has_conflicts then
    if
      line:match("..<<<<<<<")
      or line:match("..|||||||")
      or line:match("..=======")
      or line:match("..>>>>>>>")
    then
      line_hl = "NeojjHunkMergeHeader"
    elseif first_char == diff_add_start or first_chars == diff_add_start_2 then
      line_hl = "NeojjDiffAdd"
    elseif first_char == diff_delete_start or first_chars == diff_delete_start_2 then
      line_hl = "NeojjDiffDelete"
    else
      line_hl = "NeojjDiffContext"
    end
  else
    if first_char == diff_add_start then
      line_hl = "NeojjDiffAdd"
    elseif first_char == diff_delete_start then
      line_hl = "NeojjDiffDelete"
    else
      line_hl = "NeojjDiffContext"
    end
  end

  return text(line, { line_hl = line_hl })
end)

M.Hunk = Component.new(function(props)
  return col.tag("Hunk")({
    text.line_hl("NeojjHunkHeader")(props.header),
    col.tag("HunkContent")(map(props.content, HunkLine)),
  }, { foldable = true, folded = props.folded or false, context = true, hunk = props.hunk })
end)

M.List = Component.new(function(props)
  local children = filter(props.items, function(x)
    return type(x) == "table"
  end)

  if props.separator then
    children = intersperse(children, text(props.separator))
  end

  local container = col

  if props.horizontal then
    container = row
  end

  return container.tag("List")(children)
end)

---@return Component[]
local function build_graph(graph, opts)
  opts = opts or { remove_dots = false }

  if type(graph) == "table" then
    return util.map(graph, function(g)
      local char = g.text
      if opts.remove_dots and vim.tbl_contains({ "", "", "", "", "•" }, char) then
        char = ""
      end

      return text(char, { highlight = string.format("NeojjGraph%s", g.color) })
    end)
  else
    return { text(graph, { highlight = "Include" }) }
  end
end

---Format a short ID (first 12 chars)
---@param id string
---@return string
local function short_id(id)
  if not id or id == "" then
    return ""
  end
  return string.sub(id, 1, 12)
end

---Build bookmark decorations
---@param bookmarks string[]|nil
---@param args table
---@return Component[]
local function build_ref(bookmarks, args)
  local ref = {}
  if args.decorate and bookmarks and #bookmarks > 0 then
    for _, bm in ipairs(bookmarks) do
      table.insert(ref, text(bm, { highlight = "NeojjBranch" }))
      table.insert(ref, text(" "))
    end
  end
  return ref
end

---Build virtual text for commit lines (right-side display)
---@param author_name string|nil
---@param date string
---@return table[]
local function build_virtual_text(author_name, date)
  return {
    { " ", "Constant" },
    { util.str_clamp(author_name or "", 30 - (#date > 10 and #date or 10)), "NeojjGraphAuthor" },
    { util.str_min_width(date, 10), "Special" },
  }
end

---Render a divergent variant row.
---@param variant NeojjChangeLogEntry
---@param opts table|nil { virtual_text = boolean } — log view sets virtual_text=true to show author+date
---@return Component
function M.DivergentVariantRow(variant, opts)
  opts = opts or {}
  local commit_short = short_id(variant.commit_id)
  local subject = vim.split(variant.description or "", "\n")[1] or ""
  local id_highlight = variant.current_working_copy and "NeojjBranchHead" or "NeojjObjectId"

  local status_parts = {}
  if variant.immutable then
    table.insert(status_parts, "immutable")
  end
  if variant.empty then
    table.insert(status_parts, "empty")
  end
  if variant.conflict then
    table.insert(status_parts, "conflict")
  end
  local status_highlight = variant.conflict and "NeojjConflict" or "NeojjSubtleText"
  local status_suffix = #status_parts > 0 and " (" .. table.concat(status_parts, ", ") .. ")" or ""

  local children = {
    text("  "),
    text("/" .. tostring(variant.change_offset), { highlight = "NeojjDivergent" }),
    text("  "),
    text(commit_short, { highlight = id_highlight }),
    text("  "),
    text(subject),
    text.highlight(status_highlight)(status_suffix),
  }

  local row_opts = {
    kind = "change",
    yankable = variant.commit_id,
    oid = variant.commit_id,
    item = variant,
  }
  if opts.virtual_text then
    local date = variant.author_date or ""
    if #date > 16 then
      date = string.sub(date, 1, 16)
    end
    row_opts.virtual_text = build_virtual_text(variant.author_name, date)
  end

  return col.tag("commit_variant")({ row(children, row_opts) }, {
    item = variant,
    oid = variant.commit_id,
    foldable = false,
  })
end

---@param commit NeojjChangeLogEntry
---@param args table
M.CommitEntry = Component.new(function(commit, _remotes, args)
  -- Divergent parent path: render parent line + indented variants
  if commit.variants then
    local change_short = short_id(commit.change_id)
    local graph = args.graph and build_graph(commit.graph or "") or { text("") }

    local ref = build_ref(commit.bookmarks, args)

    local id_highlight = commit.current_working_copy and "NeojjBranchHead" or "NeojjObjectId"

    local parent_children = {
      text(change_short, { highlight = id_highlight }),
      text(" "),
    }
    for _, g in ipairs(graph) do
      table.insert(parent_children, g)
    end
    table.insert(parent_children, text(" "))
    table.insert(parent_children, text("<divergent>", { highlight = "NeojjDivergent" }))
    table.insert(parent_children, text(" "))
    if commit.immutable then
      table.insert(parent_children, text("immutable ", { highlight = "NeojjSubtleText" }))
    end
    for _, r in ipairs(ref) do
      table.insert(parent_children, r)
    end

    local variant_rows = {}
    for _, v in ipairs(commit.variants) do
      table.insert(variant_rows, M.DivergentVariantRow(v, { virtual_text = true }))
    end

    return col.tag("divergent_parent")(vim.list_extend({ row(parent_children) }, variant_rows), {
      kind = "change",
      item = commit,
      oid = commit.change_id,
      foldable = false,
    })
  end

  -- Non-divergent path: original rendering
  local ref = build_ref(commit.bookmarks, args)

  -- Status markers
  local markers = {}
  if commit.conflict then
    table.insert(markers, text("conflict ", { highlight = "NeojjDiffDeletions" }))
  end
  if commit.empty then
    table.insert(markers, text("empty ", { highlight = "NeojjSubtleText" }))
  end
  if commit.immutable then
    table.insert(markers, text("immutable ", { highlight = "NeojjSubtleText" }))
  end

  -- Build the abbreviated IDs
  local change_short = short_id(commit.change_id)
  local commit_short = short_id(commit.commit_id)

  -- Description (first line)
  local description = commit.description or ""
  local subject = vim.split(description, "\n")[1] or ""

  -- Date display
  local date = commit.author_date or ""
  if #date > 16 then
    date = string.sub(date, 1, 16)
  end

  local details
  if args.details then
    local graph = args.graph and build_graph(commit.graph, { remove_dots = true }) or { text("") }
    local desc_lines = vim.split(description, "\n")

    details = col.padding_left(#change_short + 1) {
      row(util.merge(graph, {
        text(" "),
        text("Commit ID:  ", { highlight = "NeojjSubtleText" }),
        text(commit_short, { highlight = "NeojjObjectId" }),
      })),
      row(util.merge(graph, {
        text(" "),
        text("Author:     ", { highlight = "NeojjSubtleText" }),
        text(commit.author_name or "", { highlight = "NeojjGraphAuthor" }),
        text(" <"),
        text(commit.author_email or ""),
        text(">"),
      })),
      row(util.merge(graph, {
        text(" "),
        text("Date:       ", { highlight = "NeojjSubtleText" }),
        text(commit.author_date or ""),
      })),
      row(graph),
      col(
        flat_map(desc_lines, function(line)
          local lines = vim.split(line, "\\n")
          lines = map(lines, function(l)
            return row(util.merge(graph, { text(" "), text(l) }))
          end)

          if #lines > 2 then
            return util.merge({ row(graph) }, lines, { row(graph) })
          elseif #lines > 1 then
            return util.merge({ row(graph) }, lines)
          else
            return lines
          end
        end),
        { highlight = "NeojjCommitViewDescription" }
      ),
    }
  end

  local graph = args.graph and build_graph(commit.graph) or { text("") }

  -- Working copy marker
  local id_highlight = "NeojjObjectId"
  if commit.current_working_copy then
    id_highlight = "NeojjBranchHead"
  end

  return col.tag("commit")({
    row(
      util.merge({
        text(change_short, { highlight = id_highlight }),
        text(" "),
      }, graph, { text(" ") }, markers, ref, { text(subject) }),
      {
        virtual_text = build_virtual_text(commit.author_name, date),
      }
    ),
    details,
  }, {
    kind = "change",
    item = commit,
    oid = commit.change_id,
    foldable = args.details == true,
    folded = true,
  })
end)

M.CommitGraph = Component.new(function(commit, padding)
  return col.tag("graph").padding_left(padding) { row(build_graph(commit.graph)) }
end)

M.Grid = Component.new(function(props)
  props = vim.tbl_extend("force", {
    -- Gap between columns
    gap = 0,
    columns = true, -- whether the items represents a list of columns instead of a list of row
    items = {},
  }, props)

  --- Transpose
  if props.columns then
    local new_items = {}
    local row_count = 0
    for i = 1, #props.items do
      local l = #props.items[i]

      if l > row_count then
        row_count = l
      end
    end
    for _ = 1, row_count do
      table.insert(new_items, {})
    end
    for i = 1, #props.items do
      for j = 1, row_count do
        local x = props.items[i][j] or text("")
        table.insert(new_items[j], x)
      end
    end
    props.items = new_items
  end

  local rendered = {}
  local column_widths = {}

  for i = 1, #props.items do
    local children = {}

    local r = props.items[i]

    for j = 1, #r do
      local item = r[j]
      local c = props.render_item(item)

      if c.tag ~= "text" and c.tag ~= "row" then
        error("Grid component only supports text and row components for now")
      end

      local c_width = c:get_width()
      children[j] = c

      -- Compute the maximum element width of each column to pad all columns to the same vertical line
      if c_width > (column_widths[j] or 0) then
        column_widths[j] = c_width
      end
    end

    rendered[i] = row(children)
  end

  for i = 1, #rendered do
    -- current row
    local r = rendered[i]

    -- Draw each column of the current row
    for j = 1, #r.children do
      local item = r.children[j]
      local gap_str = ""
      local column_width = column_widths[j] or 0

      -- Intersperse each column item with a gap
      if j ~= 1 then
        gap_str = string.rep(" ", props.gap)
      end

      if item.tag == "text" then
        item.value = gap_str .. string.format("%" .. column_width .. "s", item.value)
      elseif item.tag == "row" then
        table.insert(item.children, 1, text(gap_str))
        local width = item:get_width()
        local remaining_width = column_width - width + props.gap
        table.insert(item.children, text(string.rep(" ", remaining_width)))
      else
        error("TODO")
      end
    end
  end

  return col(rendered)
end)

---Abandon a divergent variant. Handles immutable check, abandon call, notification,
---and refresh. The refresh callback is invoked only on successful abandon.
---@param item StatusItem|NeojjChangeLogEntry the variant entry (must have commit_id and change_offset)
---@param refresh fun(): nil callback to refresh whatever buffer hosted the action
function M.abandon_variant(item, refresh)
  local notification = require("neojj.lib.notification")
  local short = string.sub(item.commit_id or "", 1, 8)
  if item.immutable then
    notification.warn("Cannot abandon immutable variant " .. short, { dismiss = true })
    return
  end
  local result = jj.cli.abandon.args(item.commit_id).call()
  if result and result.code == 0 then
    notification.info("Abandoned variant " .. short, { dismiss = true })
    refresh()
  else
    notification.warn("Failed to abandon variant " .. short, { dismiss = true })
  end
end

---Abandon a normal (non-variant) change. Handles the immutable check,
---confirmation prompt, abandon call, notification, and refresh. The refresh
---callback is invoked only on successful abandon.
---@param item StatusItem|NeojjChangeLogEntry the change entry (must have change_id)
---@param refresh fun(): nil callback to refresh whatever buffer hosted the action
function M.abandon_change(item, refresh)
  local notification = require("neojj.lib.notification")
  local input = require("neojj.lib.input")
  local short = string.sub(item.change_id or "", 1, 8)
  if item.immutable then
    notification.warn("Cannot abandon immutable commit " .. short, { dismiss = true })
    return
  end
  if not input.get_permission("Abandon " .. short .. "?") then
    return
  end
  local result = jj.cli.abandon.args(item.change_id).call()
  if result and result.code == 0 then
    notification.info("Abandoned " .. short, { dismiss = true })
    refresh()
  else
    notification.warn("Failed to abandon " .. short, { dismiss = true })
  end
end

---Abandon whatever change-like entry is under the cursor: a divergent
---variant (by commit_id, no prompt), a divergent parent (warns and does
---nothing), or a normal change (by change_id, with confirmation prompt).
---@param item StatusItem|NeojjChangeLogEntry|nil the entry under the cursor
---@param refresh fun(): nil callback to refresh whatever buffer hosted the action
function M.abandon_at_cursor(item, refresh)
  if not item then
    return
  end
  if item.change_offset ~= nil then
    M.abandon_variant(item, refresh)
  elseif M.divergent_guard(item) then
    return
  elseif item.change_id then
    M.abandon_change(item, refresh)
  end
end

---Returns true and shows a notification if the item is a divergent parent.
---Callers should early-return when this returns true.
---@param item StatusItem|NeojjChangeLogEntry|nil
---@return boolean blocked
function M.divergent_guard(item)
  if item and item.variants then
    local short = string.sub(item.change_id or "", 1, 8)
    local notification = require("neojj.lib.notification")
    notification.warn(
      string.format(
        "Change %s is divergent — move cursor to a variant line (/0, /1, ...) to operate on a specific commit.",
        short
      ),
      { dismiss = true }
    )
    return true
  end
  return false
end

return M
