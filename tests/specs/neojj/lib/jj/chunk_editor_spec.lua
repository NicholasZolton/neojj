local editor = require("neojj.lib.jj.chunk_editor")

local function file(hunks)
  return { path = "file.txt", hunks = hunks }
end

local function hunk(old_from, old_len, new_from, new_len, content, selected)
  return {
    index_from = old_from,
    index_len = old_len,
    disk_from = new_from,
    disk_len = new_len,
    lines = content,
    selected = selected,
  }
end

local function replacement(selected)
  return file { hunk(1, 3, 1, 3, { " first", "-old", "+new", " last" }, selected) }
end

describe("chunk editor", function()
  it("selects a complete replacement and discards its complement", function()
    local before, after = "first\nold\nlast\n", "first\nnew\nlast\n"
    assert.are.equal(after, editor.transform(before, after, replacement(true), false))
    assert.are.equal(before, editor.transform(before, after, replacement(true), true))
  end)

  it("selects only added lines of a replacement like Neogit", function()
    local before, after = "first\nold\nlast\n", "first\nnew\nlast\n"
    assert.are.equal(
      "first\nold\nnew\nlast\n",
      editor.transform(before, after, replacement { ["3"] = true }, false)
    )
    assert.are.equal("first\nlast\n", editor.transform(before, after, replacement { ["3"] = true }, true))
  end)

  it("selects only removed lines of a replacement", function()
    local before, after = "first\nold\nlast\n", "first\nnew\nlast\n"
    assert.are.equal("first\nlast\n", editor.transform(before, after, replacement { ["2"] = true }, false))
    assert.are.equal(
      "first\nold\nnew\nlast\n",
      editor.transform(before, after, replacement { ["2"] = true }, true)
    )
  end)

  it("keeps distant unselected hunks and unchanged gaps intact", function()
    local selection = file {
      hunk(1, 1, 1, 2, { " a", "+added" }, true),
      hunk(4, 1, 5, 1, { "-d", "+changed" }, false),
    }
    assert.are.equal(
      "a\nadded\nb\nc\nd\n",
      editor.transform("a\nb\nc\nd\n", "a\nadded\nb\nc\nchanged\n", selection, false)
    )
    assert.are.equal(
      "a\nb\nc\nchanged\n",
      editor.transform("a\nb\nc\nd\n", "a\nadded\nb\nc\nchanged\n", selection, true)
    )
  end)

  it("handles zero-length old ranges at start of a file", function()
    local selection = file { hunk(0, 0, 1, 1, { "+new" }, true) }
    assert.are.equal("new\nrest\n", editor.transform("rest\n", "new\nrest\n", selection, false))
    assert.are.equal("rest\n", editor.transform("rest\n", "new\nrest\n", selection, true))
  end)

  it("handles zero-length new ranges at start of a file", function()
    local selection = file { hunk(1, 1, 0, 0, { "-old" }, true) }
    assert.are.equal("rest\n", editor.transform("old\nrest\n", "rest\n", selection, false))
  end)

  it("preserves CRLF bytes", function()
    assert.are.equal(
      "first\r\nnew\r\nlast\r\n",
      editor.transform("first\r\nold\r\nlast\r\n", "first\r\nnew\r\nlast\r\n", replacement(true), false)
    )
  end)

  it("preserves a missing final newline", function()
    local selection = file {
      hunk(
        1,
        1,
        1,
        1,
        { "-old", "\\ No newline at end of file", "+new", "\\ No newline at end of file" },
        true
      ),
    }
    assert.are.equal("new", editor.transform("old", "new", selection, false))
    assert.are.equal("old", editor.transform("old", "new", selection, true))
  end)

  it("rejects partial replacements that would join unterminated lines", function()
    local selection = file {
      hunk(
        1,
        1,
        1,
        1,
        { "-old", "\\ No newline at end of file", "+new", "\\ No newline at end of file" },
        { ["3"] = true }
      ),
    }
    assert.has_error(function()
      editor.transform("old", "new", selection, false)
    end)
  end)

  it("creates a partial added file and removes a fully discarded addition", function()
    local selection = file { hunk(0, 0, 1, 2, { "+one", "+two" }, { ["1"] = true }) }
    assert.are.equal("one\n", editor.transform(nil, "one\ntwo\n", selection, false))
    assert.are.equal("two\n", editor.transform(nil, "one\ntwo\n", selection, true))
    selection.hunks[1].selected = true
    assert.is_nil(editor.transform(nil, "one\ntwo\n", selection, true))
  end)

  it("keeps a partially deleted file and removes a selected deletion", function()
    local selection = file { hunk(1, 2, 0, 0, { "-one", "-two" }, { ["1"] = true }) }
    assert.are.equal("two\n", editor.transform("one\ntwo\n", nil, selection, false))
    assert.are.equal("one\n", editor.transform("one\ntwo\n", nil, selection, true))
    selection.hunks[1].selected = true
    assert.is_nil(editor.transform("one\ntwo\n", nil, selection, false))
  end)

  it("distinguishes empty files from absent files for whole-file operations", function()
    assert.are.equal("", editor.transform(nil, "", { whole = true }, false))
    assert.is_nil(editor.transform(nil, "", { whole = true }, true))
  end)

  it("rejects stale changed lines, context, lengths and unrepresented changes", function()
    for _, pair in ipairs {
      { "first\nold\nlast\n", "first\nstale\nlast\n" },
      { "stale\nold\nlast\n", "first\nnew\nlast\n" },
      { "first\nold\nlast\nextra\n", "first\nnew\nlast\n" },
    } do
      assert.has_error(function()
        editor.transform(pair[1], pair[2], replacement(true), false)
      end)
    end
    local selection = replacement(true)
    selection.hunks[1].index_len = 4
    assert.has_error(function()
      editor.transform("first\nold\nlast\n", "first\nnew\nlast\n", selection, false)
    end)
  end)

  it("rejects binary chunks but permits whole-file binary selections", function()
    assert.has_error(function()
      editor.transform("old\0", "new\0", replacement(true), false)
    end)
    assert.are.equal("new\0", editor.transform("old\0", "new\0", { whole = true }, false))
  end)
end)
