local status = require("neojj.lib.jj.status")

describe("jj status parser", function()
  describe("parse_status_lines", function()
    it("parses working copy change_id and commit_id", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal("muvqvxnn", parsed.head.change_id)
      assert.are.equal("7809cff3", parsed.head.commit_id)
    end)

    it("parses parent change_id and commit_id", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal("tvonrrpo", parsed.parent.change_id)
      assert.are.equal("63990385", parsed.parent.commit_id)
    end)

    it("extracts parent description after pipe separator", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (empty) (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal("initial commit", parsed.parent.description)
    end)

    it("extracts bookmarks from parent line", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal(1, #parsed.parent.bookmarks)
      assert.are.equal("main", parsed.parent.bookmarks[1])
    end)

    it("handles multiple bookmarks on parent", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 main develop | initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal(2, #parsed.parent.bookmarks)
      assert.are.equal("main", parsed.parent.bookmarks[1])
      assert.are.equal("develop", parsed.parent.bookmarks[2])
    end)

    it("handles empty description (no description set)", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.truthy(parsed.head.description:find("no description set"))
    end)

    it("detects empty flag on working copy", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (empty) (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.is_true(parsed.head.empty)
    end)

    it("detects conflict flag on working copy", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (conflict) merging changes",
        "Parent commit (@-): tvonrrpo 63990385 initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.is_true(parsed.head.conflict)
    end)

    it("handles parent without bookmarks", function()
      local lines = {
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 initial commit",
      }
      local parsed = status.parse_status_lines(lines)
      assert.are.equal(0, #parsed.parent.bookmarks)
      assert.are.equal("initial commit", parsed.parent.description)
    end)

    it("returns empty defaults when no matching lines", function()
      local parsed = status.parse_status_lines {}
      assert.are.equal("", parsed.head.change_id)
      assert.are.equal("", parsed.parent.change_id)
    end)
  end)

  describe("parse_diff_summary", function()
    it("keeps a text-only rename displayable without treating it as a path", function()
      local label = "{old => draft.txt => new.txt}"
      local files = status.parse_diff_summary({ "R " .. label }, "/workspace")
      assert.are.same({ name = label, mode = "R" }, files[1])

      local diff = require("neojj.lib.jj.diff")
      diff.build(files[1])
      assert.are.same({}, files[1].diff.lines)
      assert.are.same({}, diff.file_diff(files[1]))
    end)

    it("parses modified file entries", function()
      local files = status.parse_diff_summary({ "M hello.txt" }, "/workspace")
      assert.are.equal(1, #files)
      assert.are.equal("M", files[1].mode)
      assert.are.equal("hello.txt", files[1].name)
    end)

    it("parses added file entries", function()
      local files = status.parse_diff_summary({ "A src.lua" }, "/workspace")
      assert.are.equal(1, #files)
      assert.are.equal("A", files[1].mode)
      assert.are.equal("src.lua", files[1].name)
    end)

    it("parses deleted file entries", function()
      local files = status.parse_diff_summary({ "D old_file.lua" }, "/workspace")
      assert.are.equal(1, #files)
      assert.are.equal("D", files[1].mode)
      assert.are.equal("old_file.lua", files[1].name)
    end)

    it("constructs absolute_path from root and name", function()
      local files = status.parse_diff_summary({ "M src/main.lua" }, "/workspace")
      assert.are.equal("/workspace/src/main.lua", files[1].absolute_path)
    end)

    it("parses multiple file entries", function()
      local files = status.parse_diff_summary({
        "M hello.txt",
        "A src.lua",
        "D old_file.lua",
      }, "/workspace")
      assert.are.equal(3, #files)
      assert.are.equal("M", files[1].mode)
      assert.are.equal("A", files[2].mode)
      assert.are.equal("D", files[3].mode)
    end)

    it("returns empty table for empty input", function()
      local files = status.parse_diff_summary({}, "/workspace")
      assert.are.equal(0, #files)
    end)

    it("skips lines that do not match the pattern", function()
      local files = status.parse_diff_summary({
        "Working copy changes:",
        "M hello.txt",
        "",
      }, "/workspace")
      assert.are.equal(1, #files)
      assert.are.equal("hello.txt", files[1].name)
    end)
  end)

  describe("parse_conflicts", function()
    it("extracts conflict file paths", function()
      local conflicts = status.parse_conflicts({
        "There are unresolved conflicts at these paths:",
        "  src/main.lua",
        "  src/util.lua",
        "",
        "Working copy  (@) : abc123 def456 (conflict)",
      }, "/workspace")
      assert.are.equal(2, #conflicts)
      assert.are.equal("src/main.lua", conflicts[1].name)
      assert.are.equal("src/util.lua", conflicts[2].name)
    end)

    it("constructs absolute_path for conflict files", function()
      local conflicts = status.parse_conflicts({
        "There are unresolved conflicts at these paths:",
        "  src/main.lua",
      }, "/workspace")
      assert.are.equal("/workspace/src/main.lua", conflicts[1].absolute_path)
    end)

    it("returns empty table when no conflicts", function()
      local conflicts = status.parse_conflicts({
        "Working copy  (@) : abc123 def456 (no description set)",
      }, "/workspace")
      assert.are.equal(0, #conflicts)
    end)

    it("stops collecting after a non-indented line", function()
      local conflicts = status.parse_conflicts({
        "There are unresolved conflicts at these paths:",
        "  src/main.lua",
        "",
        "  not/a/conflict.lua",
      }, "/workspace")
      assert.are.equal(1, #conflicts)
    end)
  end)
end)
