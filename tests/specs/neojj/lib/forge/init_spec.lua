local forge = require("neojj.lib.forge")

describe("forge", function()
  describe("provider_for_host", function()
    it("resolves github.com to the github provider", function()
      local provider = forge.provider_for_host("github.com")
      assert.is_not_nil(provider)
      assert.are.equal("github", provider.name)
    end)

    it("returns nil for unknown hosts", function()
      assert.is_nil(forge.provider_for_host("gitlab.com"))
      assert.is_nil(forge.provider_for_host("git.corp.com"))
    end)

    it("returns nil for nil host", function()
      assert.is_nil(forge.provider_for_host(nil))
    end)

    it("matches extra hosts configured per provider", function()
      local provider = forge.provider_for_host("git.corp.com", { github = { "git.corp.com" } })
      assert.is_not_nil(provider)
      assert.are.equal("github", provider.name)
    end)

    it("still matches default hosts when extra hosts are configured", function()
      local provider = forge.provider_for_host("github.com", { github = { "git.corp.com" } })
      assert.is_not_nil(provider)
      assert.are.equal("github", provider.name)
    end)
  end)

  describe("build_index", function()
    it("indexes PRs by branch name", function()
      local pr = { number = 22, title = "t", url = "u", branch = "my-feature", draft = false }
      local index = forge.build_index { pr }
      assert.are.equal(pr, index["my-feature"])
      assert.is_nil(index["other"])
    end)

    it("keeps the first PR when branches collide", function()
      local first = { number = 1, title = "a", url = "u1", branch = "dup", draft = false }
      local second = { number = 2, title = "b", url = "u2", branch = "dup", draft = false }
      local index = forge.build_index { first, second }
      assert.are.equal(first, index["dup"])
    end)

    it("returns an empty index for no PRs", function()
      assert.are.same({}, forge.build_index {})
    end)
  end)

  describe("pr_for_branch", function()
    before_each(function()
      forge.reset()
    end)

    it("returns nil when nothing is cached", function()
      assert.is_nil(forge.pr_for_branch("/some/root", "my-feature"))
    end)

    it("returns the cached PR after a successful fetch", function()
      local pr = { number = 22, title = "t", url = "u", branch = "my-feature", draft = false }
      forge._set_index("/some/root", forge.build_index { pr })
      assert.are.equal(pr, forge.pr_for_branch("/some/root", "my-feature"))
      assert.is_nil(forge.pr_for_branch("/other/root", "my-feature"))
    end)

    it("matches bookmark names carrying jj status decorations", function()
      local pr = { number = 22, title = "t", url = "u", branch = "my-feature", draft = false }
      forge._set_index("/some/root", forge.build_index { pr })
      assert.are.equal(pr, forge.pr_for_branch("/some/root", "my-feature*"))
      assert.are.equal(pr, forge.pr_for_branch("/some/root", "my-feature??"))
      assert.are.equal(pr, forge.pr_for_branch("/some/root", "my-feature@origin"))
    end)
  end)

  describe("should_fetch", function()
    it("fetches when nothing is cached", function()
      assert.is_true(forge.should_fetch(nil, 1000, false))
    end)

    it("does not retry a failure automatically, but a manual refresh does", function()
      assert.is_false(forge.should_fetch({ failed = true }, 1000, false))
      assert.is_true(forge.should_fetch({ failed = true }, 1000, true))
    end)

    it("never fetches while a fetch is in flight", function()
      assert.is_false(forge.should_fetch({ in_flight = true }, 1000, false))
      assert.is_false(forge.should_fetch({ in_flight = true }, 1000, true))
    end)

    it("skips fetching within the TTL", function()
      local entry = { index = {}, fetched_at = 1000 }
      assert.is_false(forge.should_fetch(entry, 1000 + 29000, false))
    end)

    it("fetches again once the TTL has expired", function()
      local entry = { index = {}, fetched_at = 1000 }
      assert.is_true(forge.should_fetch(entry, 1000 + 31000, false))
    end)

    it("force bypasses the TTL but not failure", function()
      local entry = { index = {}, fetched_at = 1000 }
      assert.is_true(forge.should_fetch(entry, 1000 + 1, true))
    end)
  end)

  describe("_apply_result", function()
    before_each(function()
      forge.reset()
    end)

    it("reports changed on first data", function()
      local pr = { number = 22, title = "t", url = "u", branch = "b", draft = false }
      assert.is_true(forge._apply_result("/root", { pr }, 1000))
      assert.are.equal(22, forge.pr_for_branch("/root", "b").number)
    end)

    it("reports unchanged when the same PRs arrive again", function()
      local pr = { number = 22, title = "t", url = "u", branch = "b", draft = false }
      forge._apply_result("/root", { pr }, 1000)
      assert.is_false(forge._apply_result("/root", { pr }, 2000))
    end)

    it("reports changed when a PR appears, changes, or disappears", function()
      local pr = { number = 22, title = "t", url = "u", branch = "b", draft = false }
      forge._apply_result("/root", { pr }, 1000)
      local retitled = { number = 22, title = "new", url = "u", branch = "b", draft = false }
      assert.is_true(forge._apply_result("/root", { retitled }, 2000))
      assert.is_true(forge._apply_result("/root", {}, 3000))
      assert.is_nil(forge.pr_for_branch("/root", "b"))
    end)
  end)
end)
