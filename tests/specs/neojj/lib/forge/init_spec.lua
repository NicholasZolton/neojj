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
end)
