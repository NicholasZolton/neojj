local parser = require("neojj.buffers.commit_view.parsing")

describe("commit overview parsing", function()
  it("includes modern jj binary stat lines", function()
    local overview = parser.parse_commit_overview {
      "image.png | (binary) +10 bytes",
      "notes.txt | 2 +-",
      "2 files changed, 1 insertion(+), 1 deletion(-)",
    }

    assert.are.same({
      {
        path = "image.png",
        changes = "(binary) +10 bytes",
      },
      {
        path = "notes.txt",
        changes = "2",
        insertions = "+",
        deletions = "-",
      },
    }, overview.files)
  end)

  it("continues to include Git-style binary stat lines", function()
    local overview = parser.parse_commit_overview {
      "image.png | Bin 10 -> 20 bytes",
      "1 file changed, 0 insertions(+), 0 deletions(-)",
    }

    assert.are.same({
      {
        path = "image.png",
        changes = "Bin 10 -> 20 bytes",
      },
    }, overview.files)
  end)
end)
