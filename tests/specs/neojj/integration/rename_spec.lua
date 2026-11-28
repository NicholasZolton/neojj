local async = require("plenary.async")
local harness = require("tests.util.jj_harness")
local CommitView = require("neojj.buffers.commit_view")
local chunks = require("neojj.buffers.status.chunks")
local diff = require("neojj.lib.jj.diff")
local Status = require("neojj.buffers.status")
local jj_chunks = require("neojj.lib.jj.chunks")

local source = "rules/old => draft.txt"
local destination = "rules/new name.txt"
local unrelated = "rules/draft.txt => new name.txt"
local before = { "first", "second", "third", "fourth", "fifth", "sixth" }
local after = { "first", "changed", "third", "fourth", "fifth", "sixth" }

local function fixture(colocated, modified, target)
  target = target or destination
  local root = harness.prepare_repository { colocated = colocated }
  vim.fn.mkdir(root .. "/rules")
  vim.fn.writefile(before, root .. "/" .. source)
  vim.fn.writefile({ "original unrelated" }, root .. "/" .. unrelated)
  local result = vim.system({ "jj", "new", "-m", "rename fixture" }, { cwd = root }):wait()
  assert.are.equal(0, result.code, result.stderr)
  assert.are.equal(0, vim.fn.rename(root .. "/" .. source, root .. "/" .. target))
  result = vim.system({ "jj", "status" }, { cwd = root }):wait()
  assert.are.equal(0, result.code, result.stderr)
  if modified then
    vim.fn.writefile(after, root .. "/" .. target)
  end
  vim.fn.writefile({ "edited unrelated" }, root .. "/" .. unrelated)
  return root
end

local function find_rename(items)
  for _, item in ipairs(items) do
    if item.mode == "R" then
      return item
    end
  end
end

describe("rename paths", function()
  local cwd, root, status, view, notify
  before_each(function()
    cwd = vim.fn.getcwd()
  end)

  after_each(function()
    if notify then
      vim.notify = notify
    end
    if view then
      view:close()
    end
    if status and status.buffer then
      local win = status.buffer.win_handle
      status:close()
      if win then
        assert.is_true(vim.wait(1000, function()
          return not vim.api.nvim_win_is_valid(win)
        end))
      end
    end
    if root then
      local buffer = vim.fn.bufnr(root .. "/" .. destination)
      if buffer ~= -1 then
        vim.api.nvim_buf_delete(buffer, { force = true })
      end
    end
    vim.api.nvim_set_current_dir(cwd)
    status, root, view, notify = nil, nil, nil, nil
  end)

  for _, colocated in ipairs { false, true } do
    for _, modified in ipairs { false, true } do
      it(("loads the right diff (colocated=%s, modified=%s)"):format(colocated, modified), function()
        if not harness.jj_available() then
          pending("jj binary not available")
          return
        end
        root = fixture(colocated, modified)
        local repo = require("neojj.lib.jj").repo
        repo:refresh()
        local item = assert(find_rename(repo.state.files.items))
        assert.are.equal(source, item.original_name)
        assert.are.equal(destination, item.name)

        local raw = async.util.block_on(function()
          return diff.file_diff(item, "@")
        end)
        for _, parsed in ipairs { item.diff, diff.parse(raw) } do
          assert.are.equal("renamed", parsed.kind)
          assert.are.equal(destination, parsed.file)
          assert.are.equal(modified and 1 or 0, #parsed.hunks)
          if modified then
            assert.are.same(
              { " first", "-second", "+changed", " third", " fourth", " fifth" },
              parsed.hunks[1].lines
            )
          end
        end
      end)
    end
  end

  it("opens the destination and discards only the selected rename", function()
    if not harness.jj_available() then
      pending("jj binary not available")
      return
    end
    root = fixture(false, true)
    require("neojj").setup { disable_hint = true, kind = "split" }
    require("neojj").open { cwd = root }

    local renamed
    assert.is_true(
      vim.wait(5000, function()
        status = Status.instance(root)
        if not status or not status.buffer or not status.buffer:is_visible() then
          return false
        end
        for _, section in ipairs(status.buffer.ui.item_index or {}) do
          if section.name == "files" then
            renamed = find_rename(section.items)
            return renamed ~= nil
          end
        end
        return false
      end),
      "renamed file did not render"
    )

    status.buffer:focus()
    vim.api.nvim_win_set_cursor(0, { renamed.first, 0 })
    local head = require("neojj.lib.jj").repo.state.head
    local selection = chunks.select(status.buffer.ui, false, root, head.commit_id)

    local mapping = vim.fn.maparg("<CR>", "n", false, true)
    assert.is_function(mapping.callback)
    mapping.callback()
    assert.is_true(
      vim.wait(2000, function()
        return vim.api.nvim_buf_get_name(0) == root .. "/" .. destination
      end),
      "did not open the renamed destination"
    )
    assert.are.same(after, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    local result = async.util.block_on(function()
      return jj_chunks.run(selection, "discard")
    end)
    assert.are.equal(0, result.code, table.concat(result.stderr, "\n"))
    assert.are.same(before, vim.fn.readfile(root .. "/" .. source))
    assert.are.equal(0, vim.fn.filereadable(root .. "/" .. destination))
    assert.are.same({ "edited unrelated" }, vim.fn.readfile(root .. "/" .. unrelated))
  end)

  it("does not jump to an existing file with the truncated name from a rename hunk", function()
    if not harness.jj_available() then
      pending("jj binary not available")
      return
    end
    local prefix = "rules/new"
    root = fixture(false, true, prefix .. "\nname.txt")
    vim.fn.writefile({ "wrong file" }, root .. "/" .. prefix)
    require("neojj.lib.jj").repo:refresh()
    view = async.util.block_on(function()
      return CommitView.new("@")
    end)
    view:open("split")

    local row = vim.fn.search([[\V+changed]], "w")
    assert.is_true(row > 0, "rename hunk was not rendered")
    local commit_buffer = vim.api.nvim_get_current_buf()
    local warnings = {}
    notify = vim.notify
    vim.notify = function(message, level)
      if level == vim.log.levels.WARN then
        table.insert(warnings, message)
      end
    end

    for index, key in ipairs { "a", "<CR>" } do
      local mapping = vim.fn.maparg(key, "n", false, true)
      assert.is_function(mapping.callback)
      mapping.callback()
      assert.is_true(
        vim.wait(1000, function()
          return warnings[index] ~= nil
        end),
        key .. " did not report the ambiguous path"
      )
      assert.are.equal("Unable to determine file path for diff line", warnings[index])
      assert.are.equal(commit_buffer, vim.api.nvim_get_current_buf())
    end
  end)
end)
