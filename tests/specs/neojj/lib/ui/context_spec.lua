local Ui = require("neojj.lib.ui")

describe("Ui.resolve_context", function()
  it("returns nil when options carry no kind", function()
    assert.is_nil(Ui.resolve_context(nil))
    assert.is_nil(Ui.resolve_context {})
    assert.is_nil(Ui.resolve_context { oid = "abc", yankable = "abc" })
  end)

  it("resolves a project header", function()
    local ctx = Ui.resolve_context { kind = "project" }
    assert.are.equal("project", ctx.kind)
    assert.is_nil(ctx.change_id)
    assert.are.same({}, ctx.bookmarks)
  end)

  it("resolves a bookmark line to its own name", function()
    local item = { name = "my-feature", change_id = "abcdef12" }
    local ctx = Ui.resolve_context { kind = "bookmark", item = item }
    assert.are.equal("bookmark", ctx.kind)
    assert.are.same({ "my-feature" }, ctx.bookmarks)
    assert.are.equal("abcdef12", ctx.change_id)
  end)

  it("resolves a change line from its item", function()
    local item = { change_id = "abcdef12", bookmarks = { "main", "feat" } }
    local ctx = Ui.resolve_context { kind = "change", item = item, oid = "abcdef12" }
    assert.are.equal("change", ctx.kind)
    assert.are.equal("abcdef12", ctx.change_id)
    assert.are.same({ "main", "feat" }, ctx.bookmarks)
  end)

  it("resolves a change line with node-level bookmarks (head/parent header)", function()
    local ctx = Ui.resolve_context { kind = "change", oid = "abcdef12", bookmarks = { "main" } }
    assert.are.equal("abcdef12", ctx.change_id)
    assert.are.same({ "main" }, ctx.bookmarks)
  end)

  it("prefers the item change_id over the node oid", function()
    -- Divergent variant rows set oid to a commit_id; the item carries the change_id
    local item = { change_id = "abcdef12", commit_id = "0123beef" }
    local ctx = Ui.resolve_context { kind = "change", item = item, oid = "0123beef" }
    assert.are.equal("abcdef12", ctx.change_id)
  end)

  it("resolves the commit_id from the item or the node options", function()
    local item = { change_id = "abcdef12", commit_id = "0123beef" }
    assert.are.equal("0123beef", Ui.resolve_context({ kind = "change", item = item }).commit_id)
    -- Head/parent header lines carry no item; commit_id comes from the node
    assert.are.equal("0123beef", Ui.resolve_context({ kind = "change", commit_id = "0123beef" }).commit_id)
  end)

  it("does not treat the oid as a change_id for non-change kinds", function()
    local ctx = Ui.resolve_context { kind = "file", item = { name = "foo.lua" }, oid = "0123beef" }
    assert.are.equal("file", ctx.kind)
    assert.is_nil(ctx.change_id)
    assert.are.same({}, ctx.bookmarks)
  end)
end)
