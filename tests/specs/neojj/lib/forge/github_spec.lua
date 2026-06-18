local github = require("neojj.lib.forge.github")

describe("forge.github", function()
  it("declares its identity", function()
    assert.are.equal("github", github.name)
    assert.are.equal("gh", github.executable)
    assert.are.same({ "github.com" }, github.default_hosts)
  end)

  describe("pr_list_cmd", function()
    local function flag_value(cmd, flag)
      for i, arg in ipairs(cmd) do
        if arg == flag then
          return cmd[i + 1]
        end
      end
      return nil
    end

    local cmd = github.pr_list_cmd {
      host = "github.com",
      browser_url = "https://github.com/User/repo",
      slug = "User/repo",
    }

    it("targets the remote's repo explicitly so gh works without a .git dir", function()
      assert.are.equal("gh", cmd[1])
      assert.are.equal("github.com/User/repo", flag_value(cmd, "--repo"))
    end)

    it("lists only open PRs, avoiding the slow search API", function()
      assert.are.equal("open", flag_value(cmd, "--state"))
      assert.is_nil(flag_value(cmd, "--search"))
      assert.are.equal("500", flag_value(cmd, "--limit"))
    end)
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
