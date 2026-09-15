local diff = require("neojj.lib.jj.diff")

describe("jj diff parser", function()
  describe("parse", function()
    it("handles modified files", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("modified", parsed.kind)
    end)

    it("extracts file name from modified diff header", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("hello.txt", parsed.file)
    end)

    it("extracts file name from nested path", function()
      local raw = {
        "diff --git a/src/lib/util.lua b/src/lib/util.lua",
        "index aaa..bbb 100644",
        "--- a/src/lib/util.lua",
        "+++ b/src/lib/util.lua",
        "@@ -10,3 +10,4 @@",
        " existing line",
        "+new line",
        " another line",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("src/lib/util.lua", parsed.file)
    end)

    it("handles new files", function()
      local raw = {
        "diff --git a/src.lua b/src.lua",
        "new file mode 100644",
        "index 0000000000..fa49b07797",
        "--- /dev/null",
        "+++ b/src.lua",
        "@@ -0,0 +1,1 @@",
        "+new file",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("new file", parsed.kind)
      assert.are.equal("src.lua", parsed.file)
    end)

    it("handles deleted files", function()
      local raw = {
        "diff --git a/old.lua b/old.lua",
        "deleted file mode 100644",
        "index fa49b07797..0000000000",
        "--- a/old.lua",
        "+++ /dev/null",
        "@@ -1,2 +0,0 @@",
        "-line one",
        "-line two",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("deleted file", parsed.kind)
      assert.are.equal("old.lua", parsed.file)
    end)

    it("correctly identifies hunks", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(1, #parsed.hunks)
    end)

    it("extracts from/to line numbers from hunk header", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(1, parsed.hunks[1].index_from)
      assert.are.equal(1, parsed.hunks[1].index_len)
      assert.are.equal(1, parsed.hunks[1].disk_from)
      assert.are.equal(2, parsed.hunks[1].disk_len)
    end)

    it("includes hunk content lines", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(2, #parsed.hunks[1].lines)
      assert.are.equal(" Hello world", parsed.hunks[1].lines[1])
      assert.are.equal("+modified", parsed.hunks[1].lines[2])
    end)

    it("handles multiple hunks in one file", function()
      local raw = {
        "diff --git a/file.lua b/file.lua",
        "index aaa..bbb 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@",
        " line1",
        "+added1",
        " line2",
        " line3",
        "@@ -10,2 +11,3 @@",
        " line10",
        "+added2",
        " line11",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(2, #parsed.hunks)
      assert.are.equal(1, parsed.hunks[1].index_from)
      assert.are.equal(10, parsed.hunks[2].index_from)
      assert.are.equal(11, parsed.hunks[2].disk_from)
    end)

    it("preserves diff headers inside added patch content", function()
      local raw = {
        "diff --git a/change.patch b/change.patch",
        "new file mode 100644",
        "index 0000000..abc1234",
        "--- /dev/null",
        "+++ b/change.patch",
        "@@ -0,0 +1,4 @@",
        "+--- a/hello.txt",
        "++++ b/hello.txt",
        "+@@ -1,1 +1,2 @@",
        "+ added line",
      }
      local parsed = diff.parse(raw)

      assert.are.equal(1, #parsed.hunks)
      assert.are.equal(4, #parsed.hunks[1].lines)
      assert.are.equal("++++ b/hello.txt", parsed.hunks[1].lines[2])
      assert.are.equal("+@@ -1,1 +1,2 @@", parsed.hunks[1].lines[3])
    end)

    it("sets file on each hunk", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("hello.txt", parsed.hunks[1].file)
    end)

    it("includes a hash for each hunk", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.truthy(parsed.hunks[1].hash)
      assert.is_string(parsed.hunks[1].hash)
      assert.truthy(#parsed.hunks[1].hash > 0)
    end)

    it("computes hunk length correctly", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,3 +1,4 @@",
        " line1",
        "+added",
        " line2",
        " line3",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(4, parsed.hunks[1].length)
    end)

    it("initializes stats with zero additions and deletions", function()
      local raw = {
        "diff --git a/hello.txt b/hello.txt",
        "index 802992c422..a7074a73f9 100644",
        "--- a/hello.txt",
        "+++ b/hello.txt",
        "@@ -1,1 +1,2 @@",
        " Hello world",
        "+modified",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(0, parsed.stats.additions)
      assert.are.equal(0, parsed.stats.deletions)
    end)

    it("handles new file with multiple lines", function()
      local raw = {
        "diff --git a/new.lua b/new.lua",
        "new file mode 100644",
        "index 0000000000..abcdef1234",
        "--- /dev/null",
        "+++ b/new.lua",
        "@@ -0,0 +1,3 @@",
        "+line one",
        "+line two",
        "+line three",
      }
      local parsed = diff.parse(raw)
      assert.are.equal("new file", parsed.kind)
      assert.are.equal(3, #parsed.hunks[1].lines)
    end)

    it("defaults index_len to 1 when not specified", function()
      local raw = {
        "diff --git a/one.txt b/one.txt",
        "new file mode 100644",
        "index 0000000..abc1234",
        "--- /dev/null",
        "+++ b/one.txt",
        "@@ -0,0 +1 @@",
        "+single line",
      }
      local parsed = diff.parse(raw)
      assert.are.equal(1, parsed.hunks[1].disk_len)
    end)
  end)
end)
