local harness = require("tests.util.jj_harness")
local CommitView = require("neojj.buffers.commit_view")
local jump = require("neojj.lib.jump")

local function run(root, ...)
  local cmd = { "jj", "--no-pager", "-R", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd):wait()
  assert.are.equal(0, result.code, result.stderr)
  return vim.trim(result.stdout)
end

describe("renamed file commit view navigation", function()
  local cwd, view, historical, worktree, calls
  local source = " old name.txt "
  local destination = " new name.txt "

  before_each(function()
    cwd = vim.fn.getcwd()
    historical = jump.goto_file_in_commit_at
    worktree = jump.goto_file_at
    calls = {}
    jump.goto_file_in_commit_at = function(revision, path, cursor)
      table.insert(calls, { revision = revision, path = path, cursor = cursor })
    end
    jump.goto_file_at = function(path, cursor)
      table.insert(calls, { path = path, cursor = cursor })
    end
  end)

  after_each(function()
    jump.goto_file_in_commit_at = historical
    jump.goto_file_at = worktree
    if view then
      local buf = view.buffer and view.buffer.handle
      view:close()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    view = nil
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.cmd("enew")
    vim.api.nvim_set_current_dir(cwd)
  end)

  local cases = {
    { name = "uses the source in the parent for a deleted line", line = "-old", key = "<CR>", parent = true },
    { name = "uses the destination in the commit for an added line", line = "+new", key = "<CR>" },
    { name = "uses the worktree destination even for a deleted line", line = "-old", key = "a" },
    { name = "uses the worktree destination for an added line", line = "+new", key = "a" },
  }

  for _, case in ipairs(cases) do
    it(case.name, function()
      if not harness.jj_available() then
        pending("jj binary not available")
        return
      end
      local root = harness.prepare_repository()
      vim.fn.writefile({ "first", "second", "old", "fourth", "fifth", "sixth" }, root .. "/" .. source)
      run(root, "new", "-m", "rename navigation fixture")
      assert.are.equal(0, vim.fn.rename(root .. "/" .. source, root .. "/" .. destination))
      -- Snapshot the pure rename before editing so JJ retains its copy tracking.
      run(root, "status")
      vim.fn.writefile({ "first", "second", "new", "fourth", "fifth", "sixth" }, root .. "/" .. destination)
      run(root, "status")
      require("neojj").setup { disable_hint = true, kind = "split" }
      require("neojj.lib.jj").repo:refresh()
      view = require("plenary.async").util.block_on(function()
        return CommitView.new("@")
      end)
      local renamed
      for _, diff in ipairs(view.commit_info.diffs) do
        if diff.kind == "renamed" and diff.file == destination then
          renamed = diff
        end
      end
      assert.is_not_nil(renamed, "fixture must render a real rename with an unchanged destination path")
      view:open("split")
      view.buffer:focus()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      assert.is_true(vim.fn.search("^\\V" .. case.line .. "\\m$", "W") > 0, "diff line did not render")
      local mapping = vim.fn.maparg(case.key, "n", false, true)
      assert.is_function(mapping.callback)
      mapping.callback()
      assert.are.equal(1, #calls, "mapping must invoke exactly one jump")
      local expected_revision
      if case.key == "<CR>" then
        expected_revision = view.commit_info.change_id .. (case.parent and "-" or "")
      end
      assert.are.same({
        revision = expected_revision,
        path = case.parent and source or destination,
        cursor = { case.key == "a" and case.line == "-old" and 2 or 3, 0 },
      }, calls[1])
    end)
  end
end)
