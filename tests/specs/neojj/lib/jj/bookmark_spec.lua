local bookmark = require("neojj.lib.jj.bookmark")

describe("jj bookmark parser", function()
  describe("parse_list", function()
    it("parses a local bookmark", function()
      local items = bookmark.parse_list {
        "main: tvonrrpo 63990385 initial commit",
      }
      assert.are.equal(1, #items)
      assert.are.equal("main", items[1].name)
      assert.are.equal("tvonrrpo", items[1].change_id)
      assert.are.equal("63990385", items[1].commit_id)
      assert.are.equal("initial commit", items[1].description)
      assert.is_nil(items[1].remote)
    end)

    it("parses a remote tracking bookmark", function()
      local items = bookmark.parse_list {
        "main: tvonrrpo 63990385 initial commit",
        "  @git: tvonrrpo 63990385 initial commit",
      }
      assert.are.equal(2, #items)
      assert.are.equal("main", items[2].name)
      assert.are.equal("git", items[2].remote)
      assert.are.equal("tvonrrpo", items[2].change_id)
      assert.are.equal("63990385", items[2].commit_id)
    end)

    it("handles multiple bookmarks", function()
      local items = bookmark.parse_list {
        "main: tvonrrpo 63990385 initial commit",
        "  @git: tvonrrpo 63990385 initial commit",
        "feature: muvqvxnn 7809cff3 wip",
      }
      assert.are.equal(3, #items)
      assert.are.equal("main", items[1].name)
      assert.is_nil(items[1].remote)
      assert.are.equal("main", items[2].name)
      assert.are.equal("git", items[2].remote)
      assert.are.equal("feature", items[3].name)
      assert.is_nil(items[3].remote)
    end)

    it("extracts name, change_id, commit_id, description correctly", function()
      local items = bookmark.parse_list {
        "release-v1: xyzabc12 deadbeef prepare release v1",
      }
      assert.are.equal("release-v1", items[1].name)
      assert.are.equal("xyzabc12", items[1].change_id)
      assert.are.equal("deadbeef", items[1].commit_id)
      assert.are.equal("prepare release v1", items[1].description)
    end)

    it("returns empty table for empty input", function()
      local items = bookmark.parse_list {}
      assert.are.equal(0, #items)
    end)

    it("handles description with pipe separator", function()
      local items = bookmark.parse_list {
        "main: tvonrrpo 63990385 | initial commit",
      }
      assert.are.equal(1, #items)
      assert.are.equal("initial commit", items[1].description)
    end)

    it("associates remote bookmarks with the correct parent name", function()
      local items = bookmark.parse_list {
        "main: aaa 111 first",
        "  @origin: aaa 111 first",
        "  @git: aaa 111 first",
        "dev: bbb 222 second",
        "  @git: bbb 222 second",
      }
      assert.are.equal(5, #items)
      -- Remote entries under "main"
      assert.are.equal("main", items[2].name)
      assert.are.equal("origin", items[2].remote)
      assert.are.equal("main", items[3].name)
      assert.are.equal("git", items[3].remote)
      -- Remote entries under "dev"
      assert.are.equal("dev", items[5].name)
      assert.are.equal("git", items[5].remote)
    end)

    it("handles bookmark with empty description", function()
      local items = bookmark.parse_list {
        "empty-branch: abc123 def456 ",
      }
      assert.are.equal(1, #items)
      assert.are.equal("empty-branch", items[1].name)
    end)

    it("skips lines that do not match any pattern", function()
      local items = bookmark.parse_list {
        "main: aaa 111 desc",
        "this is not a bookmark line",
        "feature: bbb 222 another",
      }
      -- "this is not a bookmark line" won't match the pattern since it has no colon-space-id-id format
      assert.are.equal(2, #items)
    end)
  end)

  describe("normalize", function()
    it("returns a plain name unchanged", function()
      assert.are.equal("main", bookmark.normalize("main"))
      assert.are.equal("nicholas/forge-pr", bookmark.normalize("nicholas/forge-pr"))
    end)

    it("strips the unpushed decoration", function()
      assert.are.equal("main", bookmark.normalize("main*"))
    end)

    it("strips the conflict decoration", function()
      assert.are.equal("main", bookmark.normalize("main??"))
    end)

    it("strips a remote qualifier", function()
      assert.are.equal("main", bookmark.normalize("main@origin"))
    end)

    it("returns nil for nil or undecorated-empty input", function()
      assert.is_nil(bookmark.normalize(nil))
      assert.is_nil(bookmark.normalize(""))
    end)
  end)
end)
