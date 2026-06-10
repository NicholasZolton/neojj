local github = require("neojj.lib.forge.github")

describe("forge.github", function()
  it("declares its identity", function()
    assert.are.equal("github", github.name)
    assert.are.equal("gh", github.executable)
    assert.are.same({ "github.com" }, github.default_hosts)
  end)

  describe("parse_prs", function()
    it("maps gh json output to normalized PRs", function()
      local stdout = vim.json.encode {
        {
          number = 22,
          title = "feat: add tracking",
          url = "https://github.com/User/repo/pull/22",
          headRefName = "my-feature",
          isCrossRepository = false,
          isDraft = false,
        },
      }
      local prs = github.parse_prs(stdout)
      assert.are.same({
        {
          number = 22,
          title = "feat: add tracking",
          url = "https://github.com/User/repo/pull/22",
          branch = "my-feature",
          draft = false,
        },
      }, prs)
    end)

    it("filters out cross-repository (fork) PRs", function()
      local stdout = vim.json.encode {
        {
          number = 5,
          title = "fork pr",
          url = "https://github.com/User/repo/pull/5",
          headRefName = "main",
          isCrossRepository = true,
          isDraft = false,
        },
        {
          number = 6,
          title = "own pr",
          url = "https://github.com/User/repo/pull/6",
          headRefName = "fix-thing",
          isCrossRepository = false,
          isDraft = true,
        },
      }
      local prs = github.parse_prs(stdout)
      assert.are.equal(1, #prs)
      assert.are.equal(6, prs[1].number)
      assert.True(prs[1].draft)
    end)

    it("returns an empty list for no PRs", function()
      assert.are.same({}, github.parse_prs("[]"))
    end)

    it("returns nil for invalid json", function()
      assert.is_nil(github.parse_prs("gh: not logged in"))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(github.parse_prs(nil))
    end)
  end)
end)
