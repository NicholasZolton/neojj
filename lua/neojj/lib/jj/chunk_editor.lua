local M = {}

local function check(ok, message)
  if not ok then
    error(message .. "; refresh status and retry", 0)
  end
end

-- Keep terminators on each line: selections must not normalize CRLF or add EOF newlines.
local function lines(content)
  local result = {}
  for line in (content or ""):gmatch("[^\n]*\n?") do
    if line ~= "" then
      table.insert(result, line)
    end
  end
  return result
end

local function text(line)
  return line and line:gsub("\n$", ""):gsub("\r$", "")
end

---Build a tree containing only selected changes (or their complement for discard).
---All cached hunks, including unselected ones, are validated against both editor trees.
---@param before string|nil
---@param after string|nil
---@param file table
---@param discard boolean
---@return string|nil
function M.transform(before, after, file, discard)
  if file.whole then
    if discard then
      return before
    end
    return after
  end

  check(
    not (before or ""):find("\0", 1, true) and not (after or ""):find("\0", 1, true),
    "Binary chunks are unsupported"
  )
  local old, new, output = lines(before), lines(after), {}
  local oi, ni = 1, 1
  local selected, changed = 0, 0

  local function unchanged()
    check(old[oi] == new[ni] and old[oi] ~= nil, "Stale diff context")
    table.insert(output, old[oi])
    oi, ni = oi + 1, ni + 1
  end

  for _, hunk in ipairs(file.hunks) do
    local old_start = hunk.index_from + (hunk.index_len == 0 and 1 or 0)
    local new_start = hunk.disk_from + (hunk.disk_len == 0 and 1 or 0)
    check(old_start >= oi and new_start >= ni, "Invalid hunk order")
    while oi < old_start and ni < new_start do
      unchanged()
    end
    check(oi == old_start and ni == new_start, "Stale hunk position")

    local old_from, new_from = oi, ni
    local previous
    for i, line in ipairs(hunk.lines) do
      local prefix, body = line:sub(1, 1), line:sub(2):gsub("\r$", "")
      local picked = hunk.selected == true
        or (type(hunk.selected) == "table" and hunk.selected[tostring(i)] == true)
      if prefix == " " then
        check(text(old[oi]) == body and text(new[ni]) == body, "Stale context line")
        previous = { old[oi], new[ni] }
        unchanged()
      elseif prefix == "-" or prefix == "+" then
        local value = prefix == "-" and old[oi] or new[ni]
        check(value ~= nil and text(value) == body, "Stale changed line")
        previous = { value }
        changed = changed + 1
        if picked then
          selected = selected + 1
        end
        local keep_change = picked
        if discard then
          keep_change = not picked
        end
        if (prefix == "+" and keep_change) or (prefix == "-" and not keep_change) then
          table.insert(output, value)
        end
        if prefix == "-" then
          oi = oi + 1
        else
          ni = ni + 1
        end
      elseif prefix == "\\" then
        check(previous ~= nil, "Invalid newline marker")
        for _, value in ipairs(previous) do
          check(value:sub(-1) ~= "\n", "Stale final newline")
        end
      else
        error("Unsupported diff line", 0)
      end
    end
    check(oi - old_from == hunk.index_len and ni - new_from == hunk.disk_len, "Stale hunk length")
  end
  while oi <= #old and ni <= #new do
    unchanged()
  end
  check(oi == #old + 1 and ni == #new + 1, "Changes outside cached hunks")

  local result = table.concat(output)
  local kept = discard and changed - selected or selected
  if (before == nil and kept == 0) or (after == nil and kept == changed) then
    return nil
  end
  -- Partial replacement of a non-newline-terminated line can concatenate lines.
  for i = 1, #output - 1 do
    check(
      output[i]:sub(-1) == "\n",
      "Selection would join unterminated lines; select the complete replacement"
    )
  end
  return result
end

local function safe_path(root, path)
  check(path ~= "" and not path:match("^[/\\]") and not path:match("^%a:"), "Invalid selection path")
  for part in path:gmatch("[^/\\]+") do
    check(part ~= ".." and part ~= ".", "Invalid selection path")
  end
  local parent = root
  local parts = vim.split(path, "/", { plain = true })
  for i = 1, #parts - 1 do
    parent = parent .. "/" .. parts[i]
    local stat = vim.uv.fs_lstat(parent)
    check(stat == nil or stat.type == "directory", "Symlink in selection path")
  end
  return root .. "/" .. path
end

local function read(path)
  local stat = vim.uv.fs_lstat(path)
  if not stat then
    return nil, nil
  end
  check(stat.type == "file", "Chunk editing requires regular files")
  local fd = assert(io.open(path, "rb"))
  local content = fd:read("*a")
  fd:close()
  return content, stat.mode
end

---Only Jujutsu's temporary right-hand tree is modified. Failure aborts its transaction.
function M.run(metadata, left, right)
  local fd = assert(io.open(metadata, "rb"))
  local selection = vim.json.decode(fd:read("*a"))
  fd:close()
  local result = vim
    .system({
      selection.jj,
      "--no-pager",
      "--ignore-working-copy",
      "-R",
      selection.root,
      "log",
      "--no-graph",
      "-r",
      "@",
      "-T",
      "commit_id",
    }, { text = true })
    :wait()
  check(result.code == 0 and vim.trim(result.stdout) == selection.commit, "Working-copy revision changed")

  local writes = {}
  for _, file in ipairs(selection.files) do
    local before, old_mode = read(safe_path(left, file.path))
    local path = safe_path(right, file.path)
    local after, new_mode = read(path)
    if not file.whole then
      check(
        old_mode == nil or new_mode == nil or bit.band(old_mode, 73) == bit.band(new_mode, 73),
        "Chunk selection cannot change file mode"
      )
    end
    table.insert(writes, {
      path = path,
      content = M.transform(before, after, file, selection.operation == "discard"),
      mode = selection.operation == "discard" and old_mode or new_mode or old_mode,
    })
  end

  -- Validate every file before writing any of them.
  for _, write in ipairs(writes) do
    if write.content == nil then
      if vim.uv.fs_lstat(write.path) then
        assert(vim.uv.fs_unlink(write.path))
      end
    else
      vim.fn.mkdir(vim.fs.dirname(write.path), "p")
      local out = assert(io.open(write.path, "wb"))
      assert(out:write(write.content))
      assert(out:close())
      if write.mode then
        assert(vim.uv.fs_chmod(write.path, write.mode))
      end
    end
  end
end

return M
