local config = require("neojj.config")
local Builder = require("neojj.lib.popup.builder")

local function with_help(fn)
  local names = { "neojj.lib.popup", "neojj.popups.help", "neojj.popups.help.actions" }
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = package.loaded[name]
    package.loaded[name] = nil
  end
  package.loaded["neojj.lib.popup"] = {
    builder = function()
      return Builder.new(function(state)
        state.show = function() end
        return state
      end)
    end,
  }
  local ok, err = pcall(function()
    fn(require("neojj.popups.help"))
  end)
  for _, name in ipairs(names) do
    package.loaded[name] = saved[name]
  end
  assert.is_true(ok, err)
end

local function entries(state)
  local result, seen = {}, {}
  for _, column in ipairs(state.actions) do
    local heading
    for _, entry in ipairs(column) do
      if entry.heading then
        heading = entry.heading
      else
        for _, key in ipairs(entry.keys) do
          assert.is_nil(seen[key], "Duplicate help key: " .. key)
          seen[key] = true
          result[key] = { heading = heading, description = entry.description }
        end
      end
    end
  end
  return result
end

local function expect(action, heading, description)
  assert.are.same({ heading = heading, description = description }, action)
end

describe("help action scopes", function()
  it("groups cursor, selected-content and navigation actions separately", function()
    with_help(function(help)
      local actions = entries(help.create { context = { section = "files" } })
      expect(actions.D, "Revisions (cursor)", "Describe")
      expect(actions.E, "Revisions (cursor)", "Edit change")
      expect(actions.O, "Revisions (cursor)", "New change on")
      expect(actions.B, "Revisions (cursor)", "New change before")
      expect(actions.F, "Bookmarks (cursor)", "Forget local / track remote")
      expect(actions.C, "Selected changes (files)", "Commit selection")
      expect(actions.S, "Selected changes (files)", "Split selection")
      expect(actions.gs, "Selected changes (files)", "Squash selection into parent")
      expect(actions.x, "Selected changes (files)", "Discard selection")
      expect(actions.o, "Navigation", "Open in browser")
      expect(actions["<cr>"], "Navigation", "Go to file")
      expect(actions["<c-r>"], "Navigation", "Refresh")
      expect(actions.c, "Commands", "Change")
    end)
  end)

  it("labels x as abandon on recent revisions without duplicating the binding", function()
    with_help(function(help)
      local actions = entries(help.create { context = { section = "recent" } })
      expect(actions.x, "Revisions (cursor)", "Abandon change")
      expect(actions.C, "Selected changes (files)", "Commit selection")
    end)
  end)

  it("distinguishes forget from delete on local bookmarks", function()
    with_help(function(help)
      local actions = entries(help.create { context = { section = "bookmarks", remote = "" } })
      expect(actions.F, "Bookmarks (cursor)", "Forget local bookmark")
      expect(actions.x, "Bookmarks (cursor)", "Delete bookmark")
    end)
  end)

  it("labels deleted bookmark restoration with its actual remote", function()
    with_help(function(help)
      local actions = entries(help.create { context = { section = "bookmarks", deleted = true } })
      expect(actions.x, "Bookmarks (cursor)", "Restore bookmark from origin")
    end)
  end)

  it("labels remote tracking and omits unsupported remote deletion", function()
    with_help(function(help)
      local actions = entries(help.create { context = { section = "bookmarks", remote = "upstream" } })
      expect(actions.F, "Bookmarks (cursor)", "Track remote bookmark")
      assert.is_nil(actions.x)
    end)
  end)

  it("does not advertise context deletion on unrelated sections", function()
    with_help(function(help)
      assert.is_nil(entries(help.create { context = { section = "tags" } }).x)
    end)
  end)

  it("supports context-free and visual help without inferring a revision selection", function()
    with_help(function(help)
      expect(entries(help.create()).x, "Selected changes (files)", "Discard selection")
      expect(entries(help.create {}).F, "Bookmarks (cursor)", "Forget local / track remote")
    end)
  end)

  it("preserves remapped chunk and context-delete keys in each group", function()
    local original = config.get_reversed_status_maps
    local mappings = vim.deepcopy(original())
    mappings.Discard = { "X" }
    mappings.CommitSelection = { "gc" }
    config.get_reversed_status_maps = function()
      return mappings
    end
    local ok, err = pcall(function()
      with_help(function(help)
        local actions = entries(help.create { context = { section = "files" } })
        expect(actions.X, "Selected changes (files)", "Discard selection")
        expect(actions.gc, "Selected changes (files)", "Commit selection")
        assert.is_nil(actions.x)
        assert.is_nil(actions.C)
        expect(
          entries(help.create { context = { section = "recent" } }).X,
          "Revisions (cursor)",
          "Abandon change"
        )
      end)
    end)
    config.get_reversed_status_maps = original
    assert.is_true(ok, err)
  end)
end)

it("captures cursor context before opening normal-mode help", function()
  local popups = require("neojj.popups")
  local original = popups.open
  local captured
  popups.open = function(name, callback)
    assert.are.equal("help", name)
    return function()
      callback(function(env)
        captured = env
      end)
    end
  end
  local ok, err = pcall(function()
    local ui = {
      get_current_section = function()
        return { options = { section = "bookmarks" } }
      end,
      get_item_under_cursor = function()
        return { remote = "upstream", deleted = true }
      end,
      get_commit_under_cursor = function()
        return "change-id"
      end,
      get_selection = function()
        error("Normal help must not read stale visual selection")
      end,
    }
    require("neojj.buffers.status.actions").n_help_popup { buffer = { ui = ui } }()
    assert.are.same({ section = "bookmarks", remote = "upstream", deleted = true }, captured.context)
    assert.are.equal("bookmarks", captured.diff.section.name)
    assert.are.equal("change-id", captured.diff.item.name)
  end)
  popups.open = original
  assert.is_true(ok, err)
end)
