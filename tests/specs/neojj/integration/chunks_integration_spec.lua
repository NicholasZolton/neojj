local harness = require("tests.util.jj_harness")
local chunks = require("neojj.lib.jj.chunks")
local diff = require("neojj.lib.jj.diff")
local Repo = require("neojj.lib.jj.repository").Repo

local function jj(root, ...)
  local cmd = { "jj", "--no-pager", "--color=never", "-R", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd):wait()
  assert.are.equal(0, result.code, table.concat(cmd, " ") .. "\n" .. result.stderr)
  return result.stdout
end

local function write(root, path, bytes)
  local fd = assert(io.open(root .. "/" .. path, "wb"))
  assert(fd:write(bytes))
  assert(fd:close())
end

local function read(root, path)
  local fd = io.open(root .. "/" .. path, "rb")
  if not fd then
    return nil
  end
  local bytes = fd:read("*a")
  fd:close()
  return bytes
end

local function content(root, rev, path)
  return jj(root, "file", "show", "-r", rev, "root-file:" .. vim.json.encode(path))
end

local function capture(root, path, whole)
  local raw = jj(root, "diff", "--git", "--", "root-file:" .. vim.json.encode(path))
  local parsed = diff.parse(vim.split(raw:gsub("\n$", ""), "\n", { plain = true }))
  return {
    root = root,
    commit = vim.trim(jj(root, "log", "--no-graph", "-r", "@", "-T", "commit_id")),
    files = { { path = path, hunks = parsed.hunks, whole = whole or false } },
  }
end

local function execute(selection, operation, message)
  local result = require("plenary.async").util.block_on(function()
    return chunks.run(selection, operation, message)
  end, 10000)
  assert.is_not_nil(result)
  assert.are.equal(0, result.code, vim.inspect(result))
end

local function lines(first, last)
  local result = {}
  for i = 1, 30 do
    result[i] = "line " .. i
  end
  result[2] = first or result[2]
  result[28] = last or result[28]
  return table.concat(result, "\n") .. "\n"
end

local function prepare()
  local root = harness.prepare_repository { cd = true }
  write(root, "a.txt", lines())
  jj(root, "describe", "-m", "chunk base")
  jj(root, "new")
  Repo.instance():refresh()
  return root
end

describe("jj chunk operations in real workspaces", function()
  local cwd
  before_each(function()
    cwd = vim.fn.getcwd()
  end)
  after_each(function()
    vim.api.nvim_set_current_dir(cwd)
  end)

  for _, operation in ipairs { "discard", "split", "commit", "squash" } do
    it(operation .. " selects one of two distant hunks without touching another file", function()
      local root = prepare()
      write(root, "a.txt", lines("first changed", "last changed"))
      write(root, "b.txt", "other change\n")
      local selection = capture(root, "a.txt")
      assert.are.equal(2, #selection.files[1].hunks)
      selection.files[1].hunks[1].selected = true
      -- Status may display an abbreviated commit ID.
      selection.commit = selection.commit:sub(1, 12)
      execute(selection, operation, "selected chunk")
      local remaining = lines(nil, "last changed")
      local selected = lines("first changed")
      local full = lines("first changed", "last changed")
      if operation == "discard" then
        assert.are.equal(remaining, content(root, "@", "a.txt"))
        assert.are.equal(lines(), content(root, "@-", "a.txt"))
        assert.are.equal(remaining, read(root, "a.txt"))
      else
        assert.are.equal(full, content(root, "@", "a.txt"))
        assert.are.equal(selected, content(root, "@-", "a.txt"))
        assert.are.equal(full, read(root, "a.txt"))
        local description = vim.trim(jj(root, "log", "--no-graph", "-r", "@-", "-T", "description"))
        assert.are.equal(operation == "squash" and "chunk base" or "selected chunk", description)
      end
      assert.are.equal("other change\n", content(root, "@", "b.txt"))
      assert.are.equal("hello world\n", content(root, "@-", "b.txt"))
      assert.are.equal("other change\n", read(root, "b.txt"))
    end)
  end

  for _, cancel in ipairs { false, true } do
    it(
      cancel and "aborts cleanly when the description editor is cancelled"
        or "uses the description editor for multiline chunk commits",
      function()
        local root = prepare()
        write(root, "a.txt", lines("selected", "remaining"))
        local selection = capture(root, "a.txt")
        selection.files[1].hunks[1].selected = true
        local script = vim.fn.tempname() .. ".lua"
        local editor_body = cancel and 'vim.cmd("cquit 1")'
          or 'vim.fn.writefile({"subject", "", "description body"}, arg[1])'
        vim.fn.writefile({ editor_body }, script)
        local client = package.loaded["neojj.client"]
        package.loaded["neojj.client"] = {
          get_envs_git_editor = function(show_diff)
            assert.is_false(show_diff)
            return { JJ_EDITOR = string.format("%q --clean --headless -l %q", vim.v.progpath, script) }
          end,
        }
        local ok, err = pcall(function()
          local result = require("plenary.async").util.block_on(function()
            return chunks.run(selection, "commit")
          end, 10000)
          if cancel then
            assert.are_not.equal(0, result.code)
            assert.are.equal(
              selection.commit,
              vim.trim(jj(root, "log", "--no-graph", "-r", "@", "-T", "commit_id"))
            )
            assert.are.equal(lines(), content(root, "@-", "a.txt"))
          else
            assert.are.equal(0, result.code, vim.inspect(result))
            assert.are.equal(
              "subject\n\ndescription body",
              vim.trim(jj(root, "log", "--no-graph", "-r", "@-", "-T", "description"))
            )
            assert.are.equal(lines("selected"), content(root, "@-", "a.txt"))
          end
          assert.are.equal(lines("selected", "remaining"), read(root, "a.txt"))
        end)
        package.loaded["neojj.client"] = client
        vim.fn.delete(script)
        assert.is_true(ok, err)
      end
    )
  end

  it("commits literal diff rows without guessing replacement pairs", function()
    local root = prepare()
    write(root, "a.txt", lines():gsub("line 2\nline 3\n", "two\nthree\n"))
    local selection = capture(root, "a.txt")
    assert.are.equal(1, #selection.files[1].hunks)
    local hunk = selection.files[1].hunks[1]
    hunk.selected = {}
    for i, line in ipairs(hunk.lines) do
      if line == "-line 2" or line == "+two" then
        hunk.selected[tostring(i)] = true
      end
    end
    execute(selection, "commit", "one replacement")
    assert.are.equal(lines():gsub("line 2\nline 3\n", "line 3\ntwo\n"), content(root, "@-", "a.txt"))
    assert.are.equal(lines():gsub("line 2\nline 3\n", "two\nthree\n"), content(root, "@", "a.txt"))
    assert.are.equal(content(root, "@", "a.txt"), read(root, "a.txt"))
  end)

  for _, added in ipairs { true, false } do
    it("partially discards an " .. (added and "added" or "deleted") .. " file", function()
      local root = prepare()
      local path = added and "added.txt" or "a.txt"
      if added then
        write(root, path, "one\ntwo\nthree\n")
      else
        assert(os.remove(root .. "/" .. path))
      end
      local selection = capture(root, path)
      local hunk = selection.files[1].hunks[1]
      hunk.selected = {}
      for i, line in ipairs(hunk.lines) do
        if line == (added and "+two" or "-line 2") then
          hunk.selected[tostring(i)] = true
        end
      end
      execute(selection, "discard")
      local expected = added and "one\nthree\n" or "line 2\n"
      assert.are.equal(expected, read(root, path))
      assert.are.equal(expected, content(root, "@", path))
      if not added then
        assert.are.equal(lines(), content(root, "@-", path))
      else
        assert.is_false(jj(root, "file", "list", "-r", "@-"):find("added.txt", 1, true) ~= nil)
      end
    end)
  end

  it("rejects stale selections without changing bytes or snapshotted history", function()
    local root = prepare()
    write(root, "a.txt", lines("selected"))
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    write(root, "a.txt", lines("newer edit"))
    jj(root, "status")
    local history = jj(root, "log", "--no-graph", "-r", "@ | @-", "-T", "commit_id")
    local bytes = read(root, "a.txt")
    local ok, err = require("plenary.async").util.block_on(function()
      return pcall(chunks.run, selection, "discard")
    end, 10000)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("Working copy changed since status was rendered", 1, true))
    assert.are.equal(bytes, read(root, "a.txt"))
    assert.are.equal(history, jj(root, "log", "--no-graph", "-r", "@ | @-", "-T", "commit_id"))
  end)

  it("recovers discarded chunks with jj undo", function()
    local root = prepare()
    local bytes = lines("recover me", "keep me")
    write(root, "a.txt", bytes)
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    execute(selection, "discard")
    assert.are_not.equal(bytes, read(root, "a.txt"))
    jj(root, "undo")
    assert.are.equal(bytes, read(root, "a.txt"))
    assert.are.equal(bytes, content(root, "@", "a.txt"))
    assert.are.equal(lines(), content(root, "@-", "a.txt"))
  end)

  it("commits chunks and whole files together without interpreting path metacharacters", function()
    local root = prepare()
    local path = "with (parentheses) | all().txt"
    write(root, path, "old\n")
    jj(root, "describe", "-m", "path base")
    jj(root, "new")
    write(root, path, "new\n")
    write(root, "a.txt", lines("selected", "remaining"))
    write(root, "b.txt", "unselected\n")
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    table.insert(selection.files, { path = path, whole = true })
    execute(selection, "commit", "multiple files")
    assert.are.equal(lines("selected"), content(root, "@-", "a.txt"))
    assert.are.equal("new\n", content(root, "@-", path))
    assert.are.equal("hello world\n", content(root, "@-", "b.txt"))
    assert.are.equal("unselected\n", read(root, "b.txt"))
  end)

  it("rejects mixing a whole rename with chunks instead of dropping its source path", function()
    local root = prepare()
    write(root, "a.txt", lines("selected"))
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    table.insert(selection.files, { path = "new.txt", original_path = "b.txt", whole = true })
    local ok, err = require("plenary.async").util.block_on(function()
      return pcall(chunks.run, selection, "discard")
    end, 10000)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("cannot be mixed with chunks", 1, true))
    assert.are.equal("hello world\n", read(root, "b.txt"))
    assert.are.equal(lines("selected"), read(root, "a.txt"))
  end)

  it("aborts the entire transaction if a later file fails hunk validation", function()
    local root = prepare()
    write(root, "a.txt", lines("selected"))
    write(root, "b.txt", "changed\n")
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    local other = capture(root, "b.txt").files[1]
    other.hunks[1].selected = true
    other.hunks[1].lines[1] = "-not the cached content"
    table.insert(selection.files, other)
    local before = jj(root, "log", "--no-graph", "-r", "@", "-T", "commit_id")
    local result = require("plenary.async").util.block_on(function()
      return chunks.run(selection, "discard")
    end, 10000)
    assert.are_not.equal(0, result.code)
    assert.are.equal(lines("selected"), read(root, "a.txt"))
    assert.are.equal("changed\n", read(root, "b.txt"))
    assert.are.equal(before, jj(root, "log", "--no-graph", "-r", "@", "-T", "commit_id"))
  end)

  for _, ending in ipairs { "\r\n", "" } do
    it(
      "preserves " .. (ending == "" and "missing EOF newline" or "CRLF bytes") .. " in real transactions",
      function()
        local root = prepare()
        local path = "endings.txt"
        write(root, path, "old" .. ending)
        jj(root, "describe", "-m", "endings base")
        jj(root, "new")
        write(root, path, "new" .. ending)
        local selection = capture(root, path)
        selection.files[1].hunks[1].selected = true
        execute(selection, "commit", "preserve endings")
        assert.are.equal("new" .. ending, read(root, path))
        assert.are.equal("new" .. ending, content(root, "@-", path))
        assert.are.equal("old" .. ending, content(root, "@--", path))
      end
    )
  end

  it("preserves executable file mode when discarding a chunk", function()
    local root = prepare()
    assert(vim.uv.fs_chmod(root .. "/a.txt", 493))
    jj(root, "describe", "-m", "executable base")
    jj(root, "new")
    write(root, "a.txt", lines("selected", "remaining"))
    local selection = capture(root, "a.txt")
    selection.files[1].hunks[1].selected = true
    execute(selection, "discard")
    assert.are.equal(lines(nil, "remaining"), read(root, "a.txt"))
    assert.are.equal(73, bit.band(vim.uv.fs_stat(root .. "/a.txt").mode, 73))
  end)

  it("rejects chunk commands in conflicted revisions without changing files", function()
    local root = prepare()
    write(root, "a.txt", lines("left"))
    jj(root, "describe", "-m", "left")
    local left = vim.trim(jj(root, "log", "--no-graph", "-r", "@", "-T", "commit_id"))
    jj(root, "new", "@-")
    write(root, "a.txt", lines("right"))
    jj(root, "describe", "-m", "right")
    jj(root, "new", left, "@")
    local selection = capture(root, "a.txt")
    local before = read(root, "a.txt")
    local ok, err = require("plenary.async").util.block_on(function()
      return pcall(chunks.run, selection, "discard")
    end, 10000)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("conflict-free revisions", 1, true))
    assert.are.equal(before, read(root, "a.txt"))
  end)

  it("rejects symlink chunks and restores symlinks with whole-file selection", function()
    local root = prepare()
    assert(vim.uv.fs_symlink("old-target", root .. "/link"))
    jj(root, "describe", "-m", "symlink base")
    jj(root, "new")
    assert(vim.uv.fs_unlink(root .. "/link"))
    assert(vim.uv.fs_symlink("new-target", root .. "/link"))
    local selection = capture(root, "link")
    for _, hunk in ipairs(selection.files[1].hunks) do
      hunk.selected = true
    end
    local result = require("plenary.async").util.block_on(function()
      return chunks.run(selection, "discard")
    end, 10000)
    assert.are_not.equal(0, result.code)
    assert.are.equal("new-target", vim.uv.fs_readlink(root .. "/link"))
    selection.files[1].whole = true
    execute(selection, "discard")
    assert.are.equal("old-target", vim.uv.fs_readlink(root .. "/link"))
  end)

  it("discards a whole binary file through the native path", function()
    local root = prepare()
    write(root, "binary.dat", "old\0bytes\n")
    jj(root, "describe", "-m", "binary base")
    jj(root, "new")
    write(root, "binary.dat", "new\0bytes\n")
    local selection = capture(root, "binary.dat", true)
    execute(selection, "discard")
    assert.are.equal("old\0bytes\n", read(root, "binary.dat"))
    assert.are.equal("old\0bytes\n", content(root, "@", "binary.dat"))
    assert.are.equal("old\0bytes\n", content(root, "@-", "binary.dat"))
  end)
end)
