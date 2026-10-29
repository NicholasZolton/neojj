local chunks = require("neojj.buffers.status.chunks")

local function make_ui(folded)
  local h1 =
    { index_from = 1, index_len = 2, disk_from = 1, disk_len = 2, lines = { "-old", "+new", " context" } }
  local h2 = {
    index_from = 20,
    index_len = 2,
    disk_from = 20,
    disk_len = 2,
    lines = { "-other", "+changed", " tail" },
  }
  -- Deliberately stale screen positions. Selection must use rendered components instead.
  h1.first, h1.last, h2.first, h2.last = 100, 104, 110, 114
  local second_header = folded and 4 or 9
  local item = { name = "one.txt", first = 2, last = 13, diff = { kind = "modified", hunks = { h1, h2 } } }
  local other = { name = "two.txt", first = 14, last = 19, diff = { kind = "modified", hunks = { h1 } } }
  local ui = {
    item_index = {
      { name = "files", first = 1, last = 19, items = { item, other } },
      { name = "recent", first = 20, last = 30, items = { { name = "commit", first = 21, last = 30 } } },
    },
  }
  function ui:get_component_on_line(row)
    local hunk, header
    if row >= 3 and row <= (folded and 3 or 6) then
      hunk, header = h1, 3
    elseif row >= second_header and row <= second_header + 3 then
      hunk, header = h2, second_header
    elseif row >= 15 and row <= 18 then
      hunk, header = h1, 15
    end
    if hunk then
      return {
        options = { hunk = hunk },
        row_range_abs = function()
          return header, header + 3
        end,
      }
    end
  end
  return ui
end

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
end

local function visual(from, to)
  move(from)
  vim.cmd("normal! V")
  move(to)
end

local function select(ui, is_visual)
  return chunks.select(ui, is_visual or false, "/workspace", "12345678")
end

describe("status chunk selection", function()
  before_each(function()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "content" }, 40))
  end)

  after_each(function()
    vim.cmd("normal! \27")
    vim.cmd("bwipeout!")
  end)

  it("selects whole hunk under normal cursor and ignores previous visual marks", function()
    visual(20, 25)
    vim.cmd("normal! \27")
    move(5)
    local selection = select(make_ui())
    assert.are.equal(1, #selection.files)
    assert.is_true(selection.files[1].hunks[1].selected)
    assert.is_false(selection.files[1].hunks[2].selected)
    assert.are.equal("12345678", selection.commit)
  end)

  it("selects complete files on file headers and every file on section header", function()
    move(2)
    assert.is_true(select(make_ui()).files[1].whole)
    move(1)
    local selection = select(make_ui())
    assert.are.equal(2, #selection.files)
    assert.is_true(selection.files[1].whole)
    assert.is_true(selection.files[2].whole)
  end)

  it("selects only visual changed rows, not the whole file", function()
    visual(5, 5)
    local selection = select(make_ui(), true)
    assert.are.same({ ["2"] = true }, selection.files[1].hunks[1].selected)
    assert.is_nil(selection.files[1].whole)
  end)

  it("selects partial lines across multiple hunks", function()
    visual(5, 10)
    local selection = select(make_ui(), true)
    assert.are.same({ ["2"] = true }, selection.files[1].hunks[1].selected)
    assert.is_true(selection.files[1].hunks[2].selected)
  end)

  it("selects multiple files and excludes unrelated status sections", function()
    visual(11, 25)
    local selection = select(make_ui(), true)
    assert.are.equal(2, #selection.files)
    assert.are.equal("one.txt", selection.files[1].path)
    assert.are.equal("two.txt", selection.files[2].path)
    assert.is_true(selection.files[2].whole)
    assert.are.same({ ["2"] = true }, selection.files[1].hunks[2].selected)
  end)

  it("handles upward visual selections", function()
    visual(10, 5)
    local selection = select(make_ui(), true)
    assert.are.same({ ["2"] = true }, selection.files[1].hunks[1].selected)
    assert.is_true(selection.files[1].hunks[2].selected)
  end)

  it("selects folded hunk headers and tracks rows after folded hunks", function()
    move(3)
    assert.is_true(select(make_ui(true)).files[1].hunks[1].selected)
    move(5)
    local selection = select(make_ui(true))
    assert.is_false(selection.files[1].hunks[1].selected)
    assert.is_true(selection.files[1].hunks[2].selected)
  end)

  it("rejects context-only visual selections and non-file rows", function()
    visual(6, 6)
    assert.has_error(function()
      select(make_ui(), true)
    end)
    vim.cmd("normal! \27")
    move(22)
    assert.has_error(function()
      select(make_ui())
    end)
  end)

  it("rejects chunks of renamed and conflicted files instead of broadening scope", function()
    local ui = make_ui()
    ui.item_index[1].items[1].original_name = "old.txt"
    move(5)
    assert.has_error(function()
      select(ui)
    end)
    move(2)
    assert.is_true(select(ui).files[1].whole)
    ui.item_index[1].items[1].original_name = nil
    ui.item_index[1].items[1].conflict = true
    move(5)
    assert.has_error(function()
      select(ui)
    end)
  end)
end)
