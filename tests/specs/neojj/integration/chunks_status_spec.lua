local harness = require("tests.util.jj_harness")
local input = require("neojj.lib.input")
local Status = require("neojj.buffers.status")

local function run(root, ...)
  local cmd = { "jj", "--no-pager", "-R", root }
  vim.list_extend(cmd, { ... })
  local result = vim.system(cmd):wait()
  assert.are.equal(0, result.code, result.stderr)
end

local function contents(first, last)
  local result = {}
  for i = 1, 30 do
    result[i] = "line " .. i
  end
  result[2], result[28] = first or result[2], last or result[28]
  return result
end

describe("chunk commands in rendered status", function()
  local cwd, status, permission
  before_each(function()
    cwd = vim.fn.getcwd()
    permission = input.get_permission
  end)
  after_each(function()
    input.get_permission = permission
    vim.cmd("normal! \27")
    if status then
      status:close()
    end
    status = nil
    vim.api.nvim_set_current_dir(cwd)
  end)

  it("maps normal x to one hunk and visual x to selected diff rows, then refreshes", function()
    local root = harness.prepare_repository { cd = true }
    vim.fn.writefile(contents(), root .. "/a.txt")
    run(root, "describe", "-m", "status base")
    run(root, "new")
    require("neojj").setup { disable_hint = true, kind = "split" }

    for _, visual in ipairs { false, true } do
      vim.fn.writefile(contents("first changed", "last changed"), root .. "/a.txt")
      if status then
        require("neojj.lib.jj").repo:refresh()
        status:redraw()
      else
        require("neojj").open { cwd = root }
      end
      local item
      assert.is_true(
        vim.wait(5000, function()
          status = Status.instance(root)
          if not status or not status.buffer or not status.buffer:is_visible() then
            return false
          end
          for _, section in ipairs(status.buffer.ui.item_index or {}) do
            if section.name == "files" then
              item = section.items[1]
            end
          end
          return item ~= nil
        end),
        "status files did not render"
      )
      status.buffer:focus()
      vim.api.nvim_win_set_cursor(0, { item.first, 0 })
      if item.folded then
        status:_action("n_toggle")()
      end
      assert.is_true(
        vim.wait(3000, function()
          return rawget(item, "diff") ~= nil and item.last > item.first
        end),
        "file diff did not render"
      )
      local added_row
      for row = item.first + 1, item.last do
        if
          vim.api
            .nvim_buf_get_lines(status.buffer.handle, row - 1, row, false)[1]
            :find("+first changed", 1, true)
        then
          added_row = row
          break
        end
      end
      assert.is_not_nil(added_row)
      vim.api.nvim_win_set_cursor(0, { added_row, 0 })
      if visual then
        vim.cmd("normal! V")
      end
      local confirmed = false
      input.get_permission = function()
        confirmed = true
        return true
      end
      local selected = require("neojj.buffers.status.chunks").select(status.buffer.ui, visual, root, "test")
      assert.is_nil(selected.files[1].whole)
      local mapping = vim.fn.maparg("x", visual and "v" or "n", false, true)
      assert.is_function(mapping.callback)
      mapping.callback()
      assert.is_true(
        vim.wait(5000, function()
          local history = require("neojj.runner").history
          local last = history[#history]
          if not last or last.code ~= 0 or not last.cmd:find("diffedit", 1, true) then
            return false
          end
          for _, line in ipairs(vim.api.nvim_buf_get_lines(status.buffer.handle, 0, -1, false)) do
            if line:find("+first changed", 1, true) then
              return false
            end
          end
          return vim.fn.readfile(root .. "/a.txt")[2] ~= "first changed"
        end),
        "status did not refresh after mapped command"
      )
      assert.is_true(confirmed)
      local expected = contents(nil, "last changed")
      if visual then
        table.remove(expected, 2)
      end
      assert.are.same(expected, vim.fn.readfile(root .. "/a.txt"))
      assert.is_true(vim.fn.mode() ~= "V")
    end
  end)
end)
