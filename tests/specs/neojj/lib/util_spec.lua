local util = require("neojj.lib.util")

describe("lib.util", function()
  it("removes ANSI escapes without corrupting UTF-8", function()
    assert.are.equal("națiune colorată", util.remove_ansi_escape_codes("\27[31mnațiune\27[0m colorată"))
  end)
end)
