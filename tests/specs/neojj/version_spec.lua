local version = require("neojj.version")

describe("NeoJJ version", function()
  it("exposes a semver string", function()
    assert.True(type(version.version) == "string")
    assert.True(version.version:match("^%d+%.%d+%.%d+$") ~= nil)
  end)
end)
