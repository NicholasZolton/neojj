local eq = assert.are.same
local diff = require("neojj.lib.diff_highlights")

describe("word_diff_spans", function()
  it("returns empty spans for identical strings", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("hello", "hello")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(0, distance)
  end)

  it("returns empty spans for two empty strings", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("", "")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(0, distance)
  end)

  it("handles completely different strings", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abc", "xyz")
    eq({ { 0, 3 } }, old_spans)
    eq({ { 0, 3 } }, new_spans)
    eq(1, distance)
  end)

  it("detects a word change with shared prefix and suffix", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("d.iteritems()", "d.items()")
    eq({ { 2, 11 } }, old_spans)
    eq({ { 2, 7 } }, new_spans)
    assert.is_true(distance < 0.5)
  end)

  it("detects an insertion in the middle", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("range(0, options):", "range(0, int(options)):")
    assert.is_true(#new_spans > 0)
    eq({ { 16, 18 } }, old_spans)
    assert.is_true(distance < 0.5)
  end)

  it("detects word replacement in a sentence", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("safe to read the commit number from", "safe to read build info from")
    assert.is_true(#old_spans > 0)
    assert.is_true(#new_spans > 0)
    assert.is_true(distance < 0.6)
  end)

  it("detects appended text", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("self.table[index] =", "self.table[index] = candidates")
    eq({ { 16, 19 } }, old_spans)
    assert.is_true(#new_spans > 0)
    assert.is_true(distance < 0.5)
  end)

  it("reports high distance for completely unrelated lines", function()
    local _, _, distance = diff.word_diff_spans(
      "#![allow(unreachable_pub)]",
      "// dead_code is a false positive here because rust will compile each integration test file as their own"
    )
    assert.is_true(distance > 0.6)
  end)

  it("handles deletion from one side only", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abcdef", "abef")
    eq({ { 0, 6 } }, old_spans)
    eq({ { 0, 4 } }, new_spans)
    eq(1, distance)
  end)

  it("handles insertion to one side only", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abef", "abcdef")
    eq({ { 0, 4 } }, old_spans)
    eq({ { 0, 6 } }, new_spans)
    eq(1, distance)
  end)

  it("detects a single character change", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("aaa", "aba")
    eq({ { 0, 3 } }, old_spans)
    eq({ { 0, 3 } }, new_spans)
    eq(1, distance)
  end)

  it("detects moved punctuation", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("[element,]", "[element],")
    assert.is_true(#old_spans > 0 or #new_spans > 0)
    assert.is_true(distance < 0.5)
  end)

  it("handles one empty string", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("hello", "")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(1, distance)
  end)

  it("handles other empty string", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("", "hello")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(1, distance)
  end)
end)

describe("apply", function()
  it("adds inline extmarks to paired changed lines", function()
    local extmarks = {}
    local buffer = {
      create_namespace = function()
        return 1
      end,
      get_lines = function()
        return { "-local old = true", "+local new = true" }
      end,
      set_extmark = function(_, _, line, column, options)
        table.insert(extmarks, { line = line, column = column, options = options })
      end,
    }

    diff.apply(buffer, { { first_line = 0, last_line = 2 } })

    eq(2, #extmarks)
    eq("NeojjDiffDeleteInline", extmarks[1].options.hl_group)
    eq("NeojjDiffAddInline", extmarks[2].options.hl_group)
  end)
end)
