local harness = require("tests.util.jj_harness")
local Status = require("neojj.buffers.status")

local function run(root, ...)
  local cmd = { "jj", "--no-pager", "-R", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd):wait()
  assert.are.equal(0, result.code, result.stderr)
end

describe("renamed file navigation", function()
  local cwd, status, root
  before_each(function()
    cwd = vim.fn.getcwd()
  end)
  after_each(function()
    if status then
      local win = status.buffer and status.buffer.win_handle
      status:close()
      if win then
        assert.is_true(vim.wait(1000, function()
          return not vim.api.nvim_win_is_valid(win)
        end))
      end
    end
    status = nil
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.cmd("enew")
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if root and vim.api.nvim_buf_get_name(buf):sub(1, #root + 1) == root .. "/" then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    vim.api.nvim_set_current_dir(cwd)
  end)

  it("restores both paths of a parsed rename without discarding unrelated edits", function()
    if not harness.jj_available() then
      pending("jj binary not available")
      return
    end
    root = harness.prepare_repository()
    assert.are.equal(0, vim.fn.rename(root .. "/b.txt", root .. "/renamed.txt"))
    local repo = require("neojj.lib.jj").repo
    repo:refresh()
    local item
    for _, candidate in ipairs(repo.state.files.items) do
      if candidate.mode == "R" then
        item = candidate
      end
    end
    assert.is_not_nil(item)
    local result = require("plenary.async").util.block_on(function()
      return require("neojj.lib.jj.chunks").run({
        root = root,
        commit = repo.state.head.commit_id,
        files = { { path = item.name, original_path = item.original_name, whole = true } },
      }, "discard")
    end)
    assert.are.equal(0, result.code)
    assert.are.same({ "hello world" }, vim.fn.readfile(root .. "/b.txt"))
    assert.are.equal(0, vim.fn.filereadable(root .. "/renamed.txt"))
    assert.are.same({ "line 1", "line 2 modified", "line 3" }, vim.fn.readfile(root .. "/a.txt"))
  end)

  for _, action in ipairs { "<CR>", "n_tab_open", "n_split_open", "n_vertical_split_open" } do
    it("opens the destination with " .. action, function()
      if not harness.jj_available() then
        pending("jj binary not available")
        return
      end
      root = harness.prepare_repository()
      vim.fn.mkdir(root .. "/rules")
      vim.fn.writefile({ "first", "second", "third" }, root .. "/rules/old name.txt")
      run(root, "new", "-m", "rename fixture")
      local destination = root .. "/rules/new name.txt"
      assert.are.equal(0, vim.fn.rename(root .. "/rules/old name.txt", destination))
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
              for _, item in ipairs(section.items) do
                if item.mode == "R" then
                  renamed = item
                end
              end
            end
          end
          return renamed ~= nil
        end),
        "renamed file did not render"
      )
      status.buffer:focus()
      vim.api.nvim_win_set_cursor(0, { renamed.first, 0 })
      if action == "<CR>" then
        local mapping = vim.fn.maparg("<CR>", "n", false, true)
        assert.is_function(mapping.callback)
        mapping.callback()
      else
        status:_action(action)()
      end
      assert.is_true(
        vim.wait(2000, function()
          return vim.api.nvim_buf_get_name(0) == destination
        end),
        "did not open the renamed destination"
      )
      assert.are.same({ "first", "second", "third" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)
  end
end)
