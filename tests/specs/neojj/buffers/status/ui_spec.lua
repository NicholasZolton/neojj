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

local function highlight_for_text(component, value)
  if component.value == value then
    return component.options.highlight
  end
  for _, child in ipairs(component.children or {}) do
    local highlight = highlight_for_text(child, value)
    if highlight then
      return highlight
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

describe("status reference highlights", function()
  local jj = require("neojj.lib.jj")
  local original_repo

  before_each(function()
    original_repo = rawget(jj, "repo")
    rawset(jj, "repo", { state = { worktree_root = "/workspace" } })
  end)

  after_each(function()
    rawset(jj, "repo", original_repo)
  end)

  it("de-emphasizes ordinary references while preserving bookmark state colors", function()
    local values = config.get_default_values()
    values.disable_hint = true

    local state = minimal_state()
    state.recent.items = {
      {
        change_id = "current1",
        commit_id = "current2",
        description = "current change",
        shortest_prefix = "cur",
        current_working_copy = true,
        bookmarks = { "current-bookmark" },
      },
      {
        change_id = "recentid",
        commit_id = "recent01",
        description = "recent change",
        shortest_prefix = "rec",
        bookmarks = { "other-bookmark" },
        remote_bookmarks = { "other@origin" },
        immutable = true,
      },
      { change_id = "diverge1", shortest_prefix = "div", variants = {}, immutable = true },
    }
    state.bookmarks.items = {
      { name = "local", change_id = "local-id", shortest_prefix = "loc", description = "local bookmark" },
      { name = "remote", remote = "origin", change_id = "remote-id", description = "remote bookmark" },
      { name = "conflicted", conflict = true },
      { name = "deleted", deleted = true },
    }

    local layout = status_ui.Status(state, values)

    assert.are.equal("NeojjWorkingCopy", highlight_for_text(layout[1], "cur"))
    assert.are.equal("NeojjChangeIdRest", highlight_for_text(layout[1], "rent1"))
    assert.are.equal("NeojjObjectId", highlight_for_text(layout[1], "current2"))
    assert.are.equal("NeojjBranchHead", highlight_for_text(layout[1], "current-bookmark"))
    assert.are.equal("NeojjChangeIdPrefix", highlight_for_text(layout[1], "rec"))
    assert.are.equal("NeojjChangeIdRest", highlight_for_text(layout[1], "entid"))
    assert.are.equal("NeojjObjectId", highlight_for_text(layout[1], "recent01"))
    assert.are.equal("NeojjBranch", highlight_for_text(layout[1], "other-bookmark"))
    assert.are.equal("NeojjRemote", highlight_for_text(layout[1], "other@origin"))
    assert.are.equal("NeojjChangeIdPrefix", highlight_for_text(layout[1], "div"))
    assert.are.equal("NeojjChangeIdRest", highlight_for_text(layout[1], "erge1"))
    assert.are.equal("NeojjImmutable", highlight_for_text(layout[1], " (immutable)"))
    assert.are.equal("NeojjBookmark", highlight_for_text(layout[1], "local"))
    assert.are.equal("NeojjChangeIdPrefix", highlight_for_text(layout[1], "loc"))
    assert.are.equal("NeojjChangeIdRest", highlight_for_text(layout[1], "al-id"))
    assert.is_nil(highlight_for_text(layout[1], "local bookmark"))
    assert.are.equal("NeojjRemote", highlight_for_text(layout[1], "remote@origin"))
    assert.are.equal("NeojjConflict", highlight_for_text(layout[1], "conflicted"))
    assert.are.equal("NeojjSubtleText", highlight_for_text(layout[1], "deleted"))
  end)
end)
