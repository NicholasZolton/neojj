local log = require("neojj.lib.jj.log")

describe("jj log parser", function()
  describe("parse_json_objects", function()
    it("parses concatenated JSON objects", function()
      local objects = log.parse_json_objects('{"a":1}{"b":2}{"c":3}')
      assert.are.equal(3, #objects)
      assert.are.equal(1, objects[1].a)
      assert.are.equal(2, objects[2].b)
      assert.are.equal(3, objects[3].c)
    end)

    it("handles a single JSON object", function()
      local objects = log.parse_json_objects('{"key":"value"}')
      assert.are.equal(1, #objects)
      assert.are.equal("value", objects[1].key)
    end)

    it("handles strings with braces inside", function()
      local objects = log.parse_json_objects('{"msg":"hello {world}"}{"x":1}')
      assert.are.equal(2, #objects)
      assert.are.equal("hello {world}", objects[1].msg)
      assert.are.equal(1, objects[2].x)
    end)

    it("handles escaped quotes in strings", function()
      local objects = log.parse_json_objects('{"msg":"say \\"hi\\""}{"x":2}')
      assert.are.equal(2, #objects)
      assert.are.equal('say "hi"', objects[1].msg)
      assert.are.equal(2, objects[2].x)
    end)

    it("returns empty table for empty input", function()
      local objects = log.parse_json_objects("")
      assert.are.equal(0, #objects)
    end)

    it("returns empty table for whitespace-only input", function()
      local objects = log.parse_json_objects("   ")
      assert.are.equal(0, #objects)
    end)

    it("handles nested objects", function()
      local objects = log.parse_json_objects('{"a":{"b":{"c":1}}}{"d":2}')
      assert.are.equal(2, #objects)
      assert.are.equal(1, objects[1].a.b.c)
      assert.are.equal(2, objects[2].d)
    end)

    it("handles arrays inside objects", function()
      local objects = log.parse_json_objects('{"items":[1,2,3]}')
      assert.are.equal(1, #objects)
      assert.are.equal(3, #objects[1].items)
    end)

    it("ignores leading/trailing whitespace between objects", function()
      local objects = log.parse_json_objects('  {"a":1}  {"b":2}  ')
      assert.are.equal(2, #objects)
    end)
  end)

  describe("json_to_entry", function()
    local sample_obj = {
      change_id = "muvqvxnnyrwstlmspzqvvqzmqstxmzwq",
      commit_id = "7809cff3fa826599726c858a8c387ddc46fb7a72",
      description = "add feature\n",
      author = {
        name = "Test User",
        email = "test@example.com",
        timestamp = "2026-03-07T02:38:46-05:00",
      },
    }

    it("extracts change_id", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("muvqvxnnyrwstlmspzqvvqzmqstxmzwq", entry.change_id)
    end)

    it("extracts commit_id", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("7809cff3fa826599726c858a8c387ddc46fb7a72", entry.commit_id)
    end)

    it("strips trailing newlines from description", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("add feature", entry.description)
    end)

    it("extracts author name", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("Test User", entry.author_name)
    end)

    it("extracts author email", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("test@example.com", entry.author_email)
    end)

    it("extracts author timestamp", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.equal("2026-03-07T02:38:46-05:00", entry.author_date)
    end)

    it("defaults to empty string for missing fields", function()
      local entry = log.json_to_entry {}
      assert.are.equal("", entry.change_id)
      assert.are.equal("", entry.commit_id)
      assert.are.equal("", entry.description)
      assert.are.equal("", entry.author_name)
      assert.are.equal("", entry.author_email)
      assert.are.equal("", entry.author_date)
    end)

    it("defaults to empty bookmarks table", function()
      local entry = log.json_to_entry(sample_obj)
      assert.are.same({}, entry.bookmarks)
    end)

    it("defaults boolean fields to false", function()
      local entry = log.json_to_entry(sample_obj)
      assert.is_false(entry.empty)
      assert.is_false(entry.conflict)
      assert.is_false(entry.immutable)
      assert.is_false(entry.current_working_copy)
    end)

    it("handles description without trailing newline", function()
      local entry = log.json_to_entry {
        change_id = "abc",
        commit_id = "def",
        description = "no trailing newline",
      }
      assert.are.equal("no trailing newline", entry.description)
    end)

    it("handles missing author gracefully", function()
      local entry = log.json_to_entry {
        change_id = "abc",
        commit_id = "def",
        description = "test",
      }
      assert.are.equal("", entry.author_name)
      assert.are.equal("", entry.author_email)
      assert.are.equal("", entry.author_date)
    end)

    it("takes only first line of multi-line descriptions", function()
      local entry = log.json_to_entry {
        change_id = "abc",
        commit_id = "def",
        description = "subject line\n\nmore details\nand more\n",
      }
      assert.are.equal("subject line", entry.description)
    end)
  end)

  describe("parse_enriched_lines", function()
    local function make_line(json_obj, flags)
      return vim.json.encode(json_obj) .. "\t" .. flags
    end

    local sample_json = {
      change_id = "muvqvxnnyrwstlmspzqvvqzmqstxmzwq",
      commit_id = "7809cff3fa826599726c858a8c387ddc46fb7a72",
      description = "add feature\n",
    }

    it("extracts shortest_prefix from the 7th tab field", function()
      local line = make_line(sample_json, "0\t0\t0\t0\t\t\tmuvq")
      local entries = log.parse_enriched_lines { line }
      assert.are.equal(1, #entries)
      assert.are.equal("muvq", entries[1].shortest_prefix)
    end)

    it("handles single-character shortest_prefix", function()
      local line = make_line(sample_json, "0\t0\t0\t0\t\t\tm")
      local entries = log.parse_enriched_lines { line }
      assert.are.equal("m", entries[1].shortest_prefix)
    end)

    it("sets shortest_prefix to nil when 7th field is empty", function()
      local line = make_line(sample_json, "0\t0\t0\t0\t\t")
      local entries = log.parse_enriched_lines { line }
      assert.is_nil(entries[1].shortest_prefix)
    end)

    it("parses bookmarks and shortest_prefix together", function()
      local line = make_line(sample_json, "0\t0\t0\t0\tmain,dev\torigin@main\tmuvq")
      local entries = log.parse_enriched_lines { line }
      assert.are.same({ "main", "dev" }, entries[1].bookmarks)
      assert.are.same({ "origin@main" }, entries[1].remote_bookmarks)
      assert.are.equal("muvq", entries[1].shortest_prefix)
    end)

    it("parses immutable, empty, and conflict flags", function()
      local line = make_line(sample_json, "1\t1\t1\t0\t\t\tmuvq")
      local entries = log.parse_enriched_lines { line }
      assert.is_true(entries[1].immutable)
      assert.is_true(entries[1].empty)
      assert.is_true(entries[1].conflict)
    end)

    it("skips empty lines", function()
      local entries = log.parse_enriched_lines { "", "" }
      assert.are.equal(0, #entries)
    end)

    it("parses divergent flag (4th flag field)", function()
      local line = make_line(sample_json, "0\t0\t0\t1\t\t\tmuvq\t0")
      local entries = log.parse_enriched_lines { line }
      assert.is_true(entries[1].divergent)
    end)

    it("defaults divergent to false when flag is 0", function()
      local line = make_line(sample_json, "0\t0\t0\t0\tmain\t\tmuvq\t0")
      local entries = log.parse_enriched_lines { line }
      assert.is_false(entries[1].divergent)
      assert.are.same({ "main" }, entries[1].bookmarks)
    end)

    it("parses the working-copy flag", function()
      local line = make_line(sample_json, "0\t0\t0\t0\t\t\tmuvq\t0\t1")
      local entries = log.parse_enriched_lines { line }
      assert.is_true(entries[1].current_working_copy)
    end)

    it("parses change_offset (8th tab field) for divergent entries", function()
      local line = make_line(sample_json, "0\t0\t0\t1\t\t\tmuvq\t2")
      local entries = log.parse_enriched_lines { line }
      assert.is_true(entries[1].divergent)
      assert.are.equal(2, entries[1].change_offset)
    end)

    it("ignores change_offset for non-divergent entries", function()
      -- jj's `self.change_offset()` returns 0 for non-divergent commits; we don't
      -- store it so callers can distinguish "this is a variant" via change_offset != nil.
      local line = make_line(sample_json, "0\t0\t0\t0\t\t\tmuvq\t0")
      local entries = log.parse_enriched_lines { line }
      assert.is_false(entries[1].divergent)
      assert.is_nil(entries[1].change_offset)
    end)
  end)

  describe("list_with_graph parsing helper", function()
    it("parses divergent flag from trailing tab-tag", function()
      local line =
        '○  {"change_id":"abc","commit_id":"123","description":"x","author":{"name":"","email":"","timestamp":""}}\tdivergent\t1'
      local entry = log.parse_with_graph_line(line)
      assert.is_true(entry.divergent)
      assert.are.equal("abc", entry.change_id)
      assert.are.equal(1, entry.change_offset)
    end)

    it("defaults divergent to false when trailing tag is empty", function()
      local line =
        '○  {"change_id":"abc","commit_id":"123","description":"x","author":{"name":"","email":"","timestamp":""}}\t\t'
      local entry = log.parse_with_graph_line(line)
      assert.is_false(entry.divergent)
      assert.is_nil(entry.change_offset)
    end)

    it("returns graph-only entry for connector lines", function()
      local entry = log.parse_with_graph_line("│ ╮")
      assert.is_nil(entry.change_id)
      assert.are.equal("│ ╮", entry.graph)
    end)
  end)

  describe("group_divergent", function()
    local function entry(overrides)
      return vim.tbl_extend("force", {
        change_id = "",
        commit_id = "",
        description = "",
        author_name = "",
        author_email = "",
        author_date = "",
        bookmarks = {},
        empty = false,
        conflict = false,
        immutable = false,
        current_working_copy = false,
        graph = nil,
        divergent = false,
        change_offset = nil,
        variants = nil,
      }, overrides or {})
    end

    it("returns input unchanged when nothing is divergent", function()
      local input = {
        entry { change_id = "a", commit_id = "1" },
        entry { change_id = "b", commit_id = "2" },
      }
      local out = log.group_divergent(input)
      assert.are.equal(2, #out)
      assert.are.equal("a", out[1].change_id)
      assert.are.equal("b", out[2].change_id)
      assert.is_nil(out[1].variants)
    end)

    it("collapses two divergent entries into a parent + two variants", function()
      local input = {
        entry { change_id = "x", commit_id = "1", divergent = true, change_offset = 0, description = "v1" },
        entry { change_id = "x", commit_id = "2", divergent = true, change_offset = 1, description = "v2" },
        entry { change_id = "y", commit_id = "3" },
      }
      local out = log.group_divergent(input)
      assert.are.equal(2, #out)
      local parent = out[1]
      assert.are.equal("x", parent.change_id)
      assert.are.equal("", parent.commit_id)
      assert.are.equal("", parent.description)
      assert.is_not_nil(parent.variants)
      assert.are.equal(2, #parent.variants)
      assert.are.equal(0, parent.variants[1].change_offset)
      assert.are.equal(1, parent.variants[2].change_offset)
      assert.are.equal("1", parent.variants[1].commit_id)
      assert.are.equal("2", parent.variants[2].commit_id)
      assert.are.equal("y", out[2].change_id)
    end)

    it("sorts variants by jj's change_offset, not by parser iteration order", function()
      -- Graph mode emits @ first, so a divergent variant labelled /1 by jj can
      -- arrive before /0. Output must still render /0 before /1.
      local input = {
        entry {
          change_id = "x",
          commit_id = "wc",
          divergent = true,
          change_offset = 1,
          current_working_copy = true,
        },
        entry { change_id = "x", commit_id = "other", divergent = true, change_offset = 0 },
      }
      local out = log.group_divergent(input)
      assert.are.equal(1, #out)
      local parent = out[1]
      assert.are.equal(2, #parent.variants)
      assert.are.equal(0, parent.variants[1].change_offset)
      assert.are.equal("other", parent.variants[1].commit_id)
      assert.are.equal(1, parent.variants[2].change_offset)
      assert.are.equal("wc", parent.variants[2].commit_id)
    end)

    it("treats a divergent entry alone in the revset as non-divergent", function()
      local input = {
        entry { change_id = "x", commit_id = "1", divergent = true, description = "lonely" },
        entry { change_id = "y", commit_id = "2" },
      }
      local out = log.group_divergent(input)
      assert.are.equal(2, #out)
      assert.is_nil(out[1].variants)
      assert.are.equal("x", out[1].change_id)
    end)

    it("handles three variants in order", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true, change_offset = 0 },
        entry { change_id = "x", commit_id = "b", divergent = true, change_offset = 1 },
        entry { change_id = "x", commit_id = "c", divergent = true, change_offset = 2 },
      }
      local out = log.group_divergent(input)
      assert.are.equal(1, #out)
      assert.are.equal(3, #out[1].variants)
      assert.are.equal(0, out[1].variants[1].change_offset)
      assert.are.equal(2, out[1].variants[3].change_offset)
    end)

    it("preserves intervening non-divergent entries between non-adjacent variants", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true },
        entry { change_id = "y", commit_id = "b" },
        entry { change_id = "x", commit_id = "c", divergent = true },
      }
      local out = log.group_divergent(input)
      assert.are.equal(2, #out)
      assert.is_not_nil(out[1].variants)
      assert.are.equal("x", out[1].change_id)
      assert.are.equal("y", out[2].change_id)
    end)

    it("aggregates bookmarks across variants without duplication", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true, bookmarks = { "main", "dev" } },
        entry { change_id = "x", commit_id = "b", divergent = true, bookmarks = { "dev", "feature" } },
      }
      local out = log.group_divergent(input)
      assert.are.same({ "main", "dev", "feature" }, out[1].bookmarks)
    end)

    it("sets current_working_copy on parent if any variant is the working copy", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true },
        entry { change_id = "x", commit_id = "b", divergent = true, current_working_copy = true },
      }
      local out = log.group_divergent(input)
      assert.is_true(out[1].current_working_copy)
    end)

    it("sets immutable on parent if any variant is immutable", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true },
        entry { change_id = "x", commit_id = "b", divergent = true, immutable = true },
      }
      local out = log.group_divergent(input)
      assert.is_true(out[1].immutable)
    end)

    it("drops graph-only connector lines that follow a removed variant", function()
      local input = {
        entry { change_id = "x", commit_id = "a", divergent = true, graph = "○  " },
        { change_id = nil, graph = "│ ╮" }, -- connector for the relocated variant
        entry { change_id = "x", commit_id = "b", divergent = true, graph = "│ ○  " },
        entry { change_id = "y", commit_id = "c", graph = "○  " },
      }
      local out = log.group_divergent(input)
      -- parent (took slot 1) + (connector at slot 2 dropped because slot 3 was removed... but slot 2 follows slot 1 which is the parent, not a removed slot)
      -- Actually: slot 1 = parent (kept), slot 2 = connector (kept; slot 1 was not removed), slot 3 = removed, slot 4 = y.
      -- So out should be: parent, connector, y. Let's assert that:
      assert.are.equal(3, #out)
      assert.is_not_nil(out[1].variants)
      assert.is_nil(out[2].change_id)
      assert.are.equal("y", out[3].change_id)
    end)
  end)

  describe("merge_unique_by_commit_id", function()
    local function entry(overrides)
      return vim.tbl_extend("force", { change_id = "", commit_id = "", description = "" }, overrides)
    end

    it("appends entries that aren't already in primary", function()
      local primary = { entry { commit_id = "a" }, entry { commit_id = "b" } }
      local additional = { entry { commit_id = "c" } }
      local result = log.merge_unique_by_commit_id(primary, additional)
      assert.are.equal(3, #result)
      assert.are.equal("c", result[3].commit_id)
    end)

    it("skips entries already present in primary", function()
      local primary = { entry { commit_id = "a" } }
      local additional = { entry { commit_id = "a" }, entry { commit_id = "b" } }
      log.merge_unique_by_commit_id(primary, additional)
      assert.are.equal(2, #primary)
      assert.are.equal("b", primary[2].commit_id)
    end)

    it("skips entries with empty or nil commit_id", function()
      local primary = { entry { commit_id = "a" } }
      local additional = {
        entry { commit_id = "" },
        { commit_id = nil },
        entry { commit_id = "b" },
      }
      log.merge_unique_by_commit_id(primary, additional)
      assert.are.equal(2, #primary)
      assert.are.equal("b", primary[2].commit_id)
    end)

    it("dedupes within additional too", function()
      local primary = {}
      local additional = {
        entry { commit_id = "x" },
        entry { commit_id = "x" },
        entry { commit_id = "y" },
      }
      log.merge_unique_by_commit_id(primary, additional)
      assert.are.equal(2, #primary)
    end)

    it("returns primary unchanged when additional is empty", function()
      local primary = { entry { commit_id = "a" } }
      log.merge_unique_by_commit_id(primary, {})
      assert.are.equal(1, #primary)
    end)
  end)
end)
