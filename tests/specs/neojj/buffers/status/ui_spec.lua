local status_ui = require("neojj.buffers.status.ui")
local config = require("neojj.config")

local function find_file_items(component, result)
  result = result or {}
  if component.options and component.options.kind == "file" then
    table.insert(result, component)
  end
  for _, child in ipairs(component.children or {}) do
    find_file_items(child, result)
  end
  return result
end

local function find_component_by_kind(component, kind)
  if component.options and component.options.kind == kind then
    return component
  end
  for _, child in ipairs(component.children or {}) do
    local match = find_component_by_kind(child, kind)
    if match then
      return match
    end
  end
end

local function minimal_state()
  return {
    worktree_root = "/workspace/project-name",
    head = {
      change_id = "abcdefgh",
      commit_id = "12345678",
      description = "working copy",
      bookmarks = {},
      empty = false,
      conflict = false,
    },
    parent = {
      change_id = "ijklmnop",
      commit_id = "87654321",
      description = "parent",
      bookmarks = {},
    },
    files = { items = {} },
    conflicts = { items = {} },
    recent = { items = {} },
    bookmarks = { items = {} },
  }
end

describe("status project header", function()
  it("shows the project name by default", function()
    local layout = status_ui.Status(minimal_state(), config.get_default_values())
    local project = find_component_by_kind(layout[1], "project")

    assert.is_not_nil(project)
    assert.are.equal("project-name", project.children[1].value)
  end)

  it("hides the project name when disabled", function()
    local values = config.get_default_values()
    values.disable_hint = true
    values.show_project_header = false

    local layout = status_ui.Status(minimal_state(), values)

    assert.is_nil(find_component_by_kind(layout[1], "project"))
    assert.are.equal(2, #layout[1].children)
  end)
end)

describe("status file highlights", function()
  it("colors mode labels by file state without coloring filenames", function()
    local values = config.get_default_values()
    values.disable_hint = true

    local state = {
      worktree_root = "/workspace",
      head = {
        change_id = "abcdefgh",
        commit_id = "12345678",
        description = "working copy",
        bookmarks = {},
        empty = false,
        conflict = false,
      },
      parent = {
        change_id = "ijklmnop",
        commit_id = "87654321",
        description = "parent",
        bookmarks = {},
      },
      files = {
        items = {
          { name = "modified.lua", mode = "M" },
          { name = "added.lua", mode = "A" },
          { name = "new.lua", mode = "N" },
          { name = "deleted.lua", mode = "D" },
          { name = "renamed.lua", mode = "R" },
          { name = "copied.lua", mode = "C" },
          { name = "updated.lua", mode = "U" },
          { name = "type-changed.lua", mode = "T" },
          { name = "both-deleted.lua", mode = "DD" },
          { name = "added-by-us.lua", mode = "AU" },
          { name = "deleted-by-them.lua", mode = "UD" },
          { name = "added-by-them.lua", mode = "UA" },
          { name = "deleted-by-us.lua", mode = "DU" },
          { name = "both-added.lua", mode = "AA" },
          { name = "both-modified.lua", mode = "UU" },
          { name = "unknown.lua", mode = "X" },
        },
      },
      conflicts = { items = {} },
      recent = { items = {} },
      bookmarks = { items = {} },
    }

    local layout = status_ui.Status(state, values)
    local items = find_file_items(layout[1])
    local expected = {
      M = "NeojjChangeModified",
      A = "NeojjChangeAdded",
      N = "NeojjChangeNewFile",
      D = "NeojjChangeDeleted",
      R = "NeojjChangeRenamed",
      C = "NeojjChangeCopied",
      U = "NeojjChangeUpdated",
      T = "NeojjChangeUpdated",
      DD = "NeojjChangeUnmerged",
      AU = "NeojjChangeUnmerged",
      UD = "NeojjChangeUnmerged",
      UA = "NeojjChangeUnmerged",
      DU = "NeojjChangeUnmerged",
      AA = "NeojjChangeUnmerged",
      UU = "NeojjChangeUnmerged",
      X = "NeojjFileMode",
    }

    assert.are.equal(16, #items)
    for _, item_component in ipairs(items) do
      local row = item_component.children[1]
      local mode_label = row.children[1]
      local filename = row.children[2]
      local mode = item_component.options.item.mode

      assert.are.equal(expected[mode], mode_label.options.highlight)
      assert.is_nil(filename.options.highlight)
    end
  end)
end)
