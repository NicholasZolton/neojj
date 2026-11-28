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

  for _, parser in ipairs { "parse_diff_summary", "parse_status_files" } do
    describe(parser .. " renames", function()
      local function parse(line)
        local lines = parser == "parse_status_files" and { "Working copy changes:", line } or { line }
        return status[parser](lines, "/workspace")[1]
      end

      for _, name in ipairs {
        "rules/{old.yaml => new.yaml}",
        "src/{old dir => new dir}/file.txt",
        "{old => draft.txt => new.txt}",
      } do
        it("keeps an unresolved rename display-only: " .. name, function()
          local item = parse("R " .. name)
          assert.are.same({ name = name, mode = "R" }, item)
          local diff = require("neojj.lib.jj.diff")
          diff.build(item)
          assert.are.same({}, item.diff.lines)
          assert.are.same({}, diff.file_diff(item))
        end)
      end

      it("preserves literal rename notation in ordinary filenames", function()
        local item = parse("M {old => new}.txt")
        assert.are.equal("{old => new}.txt", item.name)
        assert.is_nil(item.original_name)
      end)

      it("keeps copy mutations guarded until their source scope is supported", function()
        local item = parse("C {source => copy}.txt")
        assert.are.same({ name = "{source => copy}.txt", mode = "C" }, item)
      end)
    end)
  end

  describe("parse_diff_summary", function()
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

  describe("structured rename paths", function()
    local shell = require("neojj.lib.jj.shell")
    local exec, calls, state, status_lines, diff_lines

    before_each(function()
      exec = shell.exec
      calls = {}
      state = require("neojj.lib.jj.repository").Repo.new("/workspace").state
      status_lines = {
        "Working copy changes:",
        "R {old => draft.txt => new.txt}",
        "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
        "Parent commit (@-): tvonrrpo 63990385 initial commit",
      }
      diff_lines = { vim.json.encode { "renamed", "old => draft.txt", "new.txt" } }
      shell.exec = function(cmd, cwd)
        assert.are.equal("/workspace", cwd)
        table.insert(calls, cmd)
        if cmd[4] == "status" then
          return status_lines, 0, {}
        end
        return diff_lines, diff_lines and 0 or 1, {}
      end
    end)

    after_each(function()
      shell.exec = exec
    end)

    it("reads exact paths at the status revision without another snapshot", function()
      status.meta.update(state)
      assert.are.equal(2, #calls)
      assert.are.same({
        "jj",
        "--no-pager",
        "--color=never",
        "--ignore-working-copy",
        "diff",
        "-r",
        "7809cff3",
        "-T",
      }, vim.list_slice(calls[2], 1, 8))
      local item = state.files.items[1]
      assert.are.equal("new.txt", item.name)
      assert.are.equal("old => draft.txt", item.original_name)
      assert.are.equal("/workspace/new.txt", item.absolute_path)
    end)

    it("preserves special paths and handles other changes in the same response", function()
      local target = " new\n{literal => name}.txt "
      diff_lines = {
        vim.json.encode { "renamed", "old => draft.txt", target },
        vim.json.encode { "added", "added.txt", "added.txt" },
        vim.json.encode { "removed", "deleted.txt", "deleted.txt" },
        vim.json.encode { "modified", "edited.txt", "edited.txt" },
        vim.json.encode { "copied", "source.txt", "copy.txt" },
      }
      status.meta.update(state)
      local items = state.files.items
      assert.are.equal(5, #items)
      assert.are.equal(target, items[1].name)
      assert.are.equal("/workspace/" .. target, items[1].absolute_path)
      assert.are.equal(vim.fn.fnameescape(target), items[1].escaped_path)
      assert.are.equal("file:" .. target, items[1].fileset_path)
      assert.are.equal("A", items[2].mode)
      assert.are.equal("deleted.txt", items[3].name)
      assert.are.equal("D", items[3].mode)
      assert.are.equal("M", items[4].mode)
      assert.are.equal("copy.txt", items[5].name)
      assert.is_nil(items[5].original_name)
    end)

    for _, response in ipairs {
      { name = "failed command" },
      { name = "invalid JSON", lines = { "not JSON" } },
      { name = "unknown status", lines = { ' ["unknown","old","new"]' } },
      { name = "missing path", lines = { '["renamed","old",null]' } },
      { name = "empty path", lines = { '["renamed","old",""]' } },
      { name = "partial response", lines = { '["renamed","old","new"]', "invalid" } },
    } do
      it("leaves renames non-actionable after " .. response.name, function()
        diff_lines = response.lines
        status.meta.update(state)
        local item = state.files.items[1]
        assert.are.equal("{old => draft.txt => new.txt}", item.name)
        assert.is_nil(item.absolute_path)
        assert.is_nil(item.original_name)
        assert.are.same({}, item.diff.lines)
      end)
    end

    it("does not query metadata without a status commit", function()
      status_lines = { "Working copy changes:", "R {old => new}" }
      status.meta.update(state)
      assert.are.equal(1, #calls)
      assert.is_nil(state.files.items[1].absolute_path)
    end)

    it("does not add a query for ordinary modified files", function()
      status_lines[2] = "M file.txt"
      status.meta.update(state)
      assert.are.equal(1, #calls)
      assert.are.equal("/workspace/file.txt", state.files.items[1].absolute_path)
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
