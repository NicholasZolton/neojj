local tag = require("neojj.lib.jj.tag")

local function tag_line(fields)
  return vim.json.encode(vim.tbl_extend("force", {
    name = "tag",
    remote = vim.NIL,
    change_id = "change",
    commit_id = "commit",
    timestamp = "2026-03-08T12:00:00Z",
    description = "description",
    present = true,
    conflict = false,
    shortest_prefix = "cha",
  }, fields or {}))
end

describe("jj tag parser", function()
  it("parses local tags", function()
    local items = tag.parse_template_list {
      tag_line {
        name = "v1.0.0",
        change_id = "abcdefgh",
        commit_id = "12345678",
        description = "Release 1.0",
        shortest_prefix = "abc",
      },
    }

    assert.are.equal(1, #items)
    assert.are.equal("v1.0.0", items[1].name)
    assert.are.equal("abcdefgh", items[1].change_id)
    assert.are.equal("12345678", items[1].commit_id)
    assert.are.equal("Release 1.0", items[1].description)
    assert.is_nil(items[1].remote)
    assert.are.equal("abc", items[1].shortest_prefix)
  end)

  it("preserves tabs in descriptions", function()
    local items = tag.parse_template_list { tag_line { description = "release\tcandidate" } }
    assert.are.equal("release\tcandidate", items[1].description)
  end)

  it("preserves conflict and missing-target states", function()
    local items = tag.parse_template_list {
      tag_line { name = "conflicted", description = "ignored", conflict = true },
      tag_line { name = "deleted", description = "ignored", present = false },
    }

    assert.is_true(items[1].conflict)
    assert.are.equal("(conflicted)", items[1].description)
    assert.is_true(items[2].deleted)
    assert.are.equal("(deleted)", items[2].description)
  end)

  it("ignores incomplete lines", function()
    assert.are.same({}, tag.parse_template_list { "not\ta\ttag" })
  end)

  it("keeps previous state after a refresh failure", function()
    local saved_shell = package.loaded["neojj.lib.jj.shell"]
    package.loaded["neojj.lib.jj.shell"] = {
      exec = function()
        return nil, 1, { "tag command failed" }
      end,
    }

    local state = {
      worktree_root = "/workspace",
      tags = { items = { { name = "v1.0.0" } }, error = nil },
    }
    tag.meta.update(state)
    package.loaded["neojj.lib.jj.shell"] = saved_shell

    assert.are.same({ { name = "v1.0.0" } }, state.tags.items)
    assert.are.equal("tag command failed", state.tags.error)
  end)

  it("keeps only local tags and sorts by timestamp", function()
    local saved_shell = package.loaded["neojj.lib.jj.shell"]
    package.loaded["neojj.lib.jj.shell"] = {
      exec = function()
        return {
          tag_line {
            name = "old",
            change_id = "old",
            commit_id = "oldcommit",
            timestamp = "2026-03-01T00:00:00Z",
            description = "Old",
            shortest_prefix = "old",
          },
          tag_line {
            name = "remote",
            remote = "origin",
            change_id = "remote",
            commit_id = "remotecommit",
            timestamp = "2026-03-09T00:00:00Z",
            description = "Remote",
            shortest_prefix = "rem",
          },
          tag_line {
            name = "new",
            change_id = "new",
            commit_id = "newcommit",
            timestamp = "2026-03-08T00:00:00Z",
            description = "New",
            shortest_prefix = "new",
          },
        },
          0,
          {}
      end,
    }

    local state = { worktree_root = "/workspace", tags = { items = {}, error = "old error" } }
    tag.meta.update(state)
    package.loaded["neojj.lib.jj.shell"] = saved_shell

    assert.are.same(
      { "new", "old" },
      vim.tbl_map(function(item)
        return item.name
      end, state.tags.items)
    )
    assert.is_nil(state.tags.error)
  end)
end)
