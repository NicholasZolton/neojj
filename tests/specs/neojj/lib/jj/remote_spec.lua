local remote = require("neojj.lib.jj.remote")

describe("remote.parse", function()
  it("parses an scp-style ssh remote", function()
    local info = remote.parse("git@github.com:User/repo.git")
    assert.are.same({ host = "github.com", browser_url = "https://github.com/User/repo" }, info)
  end)

  it("parses an ssh:// remote", function()
    local info = remote.parse("ssh://git@github.com/User/repo.git")
    assert.are.same({ host = "github.com", browser_url = "https://github.com/User/repo" }, info)
  end)

  it("parses an https remote", function()
    local info = remote.parse("https://github.com/User/repo.git")
    assert.are.same({ host = "github.com", browser_url = "https://github.com/User/repo" }, info)
  end)

  it("parses an https remote without .git suffix", function()
    local info = remote.parse("https://gitlab.com/group/project")
    assert.are.same({ host = "gitlab.com", browser_url = "https://gitlab.com/group/project" }, info)
  end)

  it("parses a self-hosted ssh remote", function()
    local info = remote.parse("git@git.corp.com:team/repo.git")
    assert.are.same({ host = "git.corp.com", browser_url = "https://git.corp.com/team/repo" }, info)
  end)

  it("returns nil for an unparsable url", function()
    assert.is_nil(remote.parse("not a url"))
  end)

  it("returns nil for nil input", function()
    assert.is_nil(remote.parse(nil))
  end)
end)
