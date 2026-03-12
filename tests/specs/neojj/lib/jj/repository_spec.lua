local Repo = require("neojj.lib.jj.repository").Repo

describe("Repo:relpath", function()
  local repo

  before_each(function()
    repo = Repo.new("/home/user/project")
  end)

  it("returns relative path for file inside workspace", function()
    assert.are.equal("src/main.lua", repo:relpath("/home/user/project/src/main.lua"))
  end)

  it("returns empty string when path equals workspace root", function()
    assert.are.equal("", repo:relpath("/home/user/project"))
  end)

  it("returns nil when path is outside workspace", function()
    assert.is_nil(repo:relpath("/home/user/other/file.lua"))
  end)

  it("returns nil for completely different path", function()
    assert.is_nil(repo:relpath("/tmp/file.lua"))
  end)

  it("handles path with trailing slash on root", function()
    assert.are.equal("src/main.lua", repo:relpath("/home/user/project/src/main.lua"))
  end)
end)
