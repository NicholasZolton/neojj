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
    text(string.format("%s %s", diff.kind, diff.file), { line_hl = "NeoJJDiffHeader" }),
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
  local ok, repo = pcall(function() return jj.repo end)
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
      line_hl = "NeoJJHunkMergeHeader"
    elseif first_char == diff_add_start or first_chars == diff_add_start_2 then
      line_hl = "NeoJJDiffAdd"
    elseif first_char == diff_delete_start or first_chars == diff_delete_start_2 then
      line_hl = "NeoJJDiffDelete"
    else
      line_hl = "NeoJJDiffContext"
    end
  else
    if first_char == diff_add_start then
      line_hl = "NeoJJDiffAdd"
    elseif first_char == diff_delete_start then
      line_hl = "NeoJJDiffDelete"
    else
      line_hl = "NeoJJDiffContext"
    end
  end

  return text(line, { line_hl = line_hl })
end)

M.Hunk = Component.new(function(props)
  return col.tag("Hunk")({
    text.line_hl("NeoJJHunkHeader")(props.header),
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

      return text(char, { highlight = string.format("NeoJJGraph%s", g.color) })
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

---@param commit NeoJJChangeLogEntry
---@param args table
M.CommitEntry = Component.new(function(commit, _remotes, args)
  local ref = {}

  -- Render bookmarks as decorations
  if args.decorate and commit.bookmarks and #commit.bookmarks > 0 then
    for _, bm in ipairs(commit.bookmarks) do
      table.insert(ref, text(bm, { highlight = "NeoJJBranch" }))
      table.insert(ref, text(" "))
    end
  end

  -- Status markers
  local markers = {}
  if commit.conflict then
    table.insert(markers, text("conflict ", { highlight = "NeoJJDiffDeletions" }))
  end
  if commit.empty then
    table.insert(markers, text("empty ", { highlight = "NeoJJSubtleText" }))
  end
  if commit.immutable then
    table.insert(markers, text("immutable ", { highlight = "NeoJJSubtleText" }))
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
        text("Commit ID:  ", { highlight = "NeoJJSubtleText" }),
        text(commit_short, { highlight = "NeoJJObjectId" }),
      })),
      row(util.merge(graph, {
        text(" "),
        text("Author:     ", { highlight = "NeoJJSubtleText" }),
        text(commit.author_name or "", { highlight = "NeoJJGraphAuthor" }),
        text(" <"),
        text(commit.author_email or ""),
        text(">"),
      })),
      row(util.merge(graph, {
        text(" "),
        text("Date:       ", { highlight = "NeoJJSubtleText" }),
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
        { highlight = "NeoJJCommitViewDescription" }
      ),
    }
  end

  local graph = args.graph and build_graph(commit.graph) or { text("") }

  -- Working copy marker
  local id_highlight = "NeoJJObjectId"
  if commit.current_working_copy then
    id_highlight = "NeoJJBranchHead"
  end

  return col.tag("commit")({
    row(
      util.merge({
        text(change_short, { highlight = id_highlight }),
        text(" "),
      }, graph, { text(" ") }, markers, ref, { text(subject) }),
      {
        virtual_text = {
          { " ", "Constant" },
          {
            util.str_clamp(commit.author_name or "", 30 - (#date > 10 and #date or 10)),
            "NeoJJGraphAuthor",
          },
          { util.str_min_width(date, 10), "Special" },
        },
      }
    ),
    details,
  }, {
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

return M
