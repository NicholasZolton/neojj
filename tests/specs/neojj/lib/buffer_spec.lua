local eq = assert.are.same

local Buffer = require("neojj.lib.buffer")

describe("lib.buffer", function()
  it("uses a range extmark so word-level highlights can override it", function()
    local handle = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(handle, 0, -1, false, { "line one" })

    local buffer = Buffer:new(handle, -1)
    buffer:add_line_highlight(0, "NeojjDiffAddHighlight")

    local ns_id = buffer:get_namespace_id()
    local extmarks = vim.api.nvim_buf_get_extmarks(handle, ns_id, 0, -1, { details = true })
    eq(1, #extmarks)

    local opts = extmarks[1][4]
    eq("NeojjDiffAddHighlight", opts.hl_group)
    eq(1, opts.end_row)
    eq(0, opts.end_col)
    eq(true, opts.hl_eol)
    eq(190, opts.priority)
    eq(nil, opts.line_hl_group)
  end)

  it("suppresses visual line highlights without removing semantic metadata", function()
    local handle = vim.api.nvim_get_current_buf()
    local buffer = Buffer:new(handle, vim.api.nvim_get_current_win())
    local calls = 0
    buffer.add_line_highlight = function()
      calls = calls + 1
    end
    vim.b[handle].neojj_disable_hunk_highlight = true

    buffer:set_line_highlights { { 0, "NeojjDiffAdd" } }

    vim.b[handle].neojj_disable_hunk_highlight = nil
    assert.are.equal(0, calls)
  end)

  it("can reuse a named buffer after opening a terminal channel", function()
    local name = "NeojjConsoleTest-" .. vim.fn.getpid()
    local first = Buffer.create {
      name = name,
      open = false,
      buftype = false,
      after = function(buffer)
        buffer:open_terminal_channel()
      end,
    }

    local ok, second = pcall(Buffer.create, {
      name = name,
      open = false,
      buftype = false,
      after = function(buffer)
        buffer:open_terminal_channel()
      end,
    })

    pcall(function()
      first:close_terminal_channel()
    end)
    if second then
      pcall(function()
        second:close_terminal_channel()
      end)
    end
    local existing = vim.fn.bufnr(name)
    if existing ~= -1 then
      pcall(vim.api.nvim_buf_delete, existing, { force = true })
    end

    assert.is_true(ok)
  end)

  it("restores the original buffer when closing a replacement", function()
    local original_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local replacement_tab = vim.api.nvim_get_current_tabpage()
    local original_buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(original_buffer)
    local tab_count = #vim.api.nvim_list_tabpages()

    local replacement = Buffer.create {
      name = "NeojjReplaceTest-" .. vim.fn.getpid(),
      kind = "replace",
      filetype = "NeojjReplaceTest",
    }
    replacement:close(true)

    local tab_still_exists = vim.api.nvim_tabpage_is_valid(replacement_tab)
    local current_buffer = tab_still_exists and vim.api.nvim_get_current_buf() or nil

    if tab_still_exists then
      vim.cmd("tabclose!")
    end
    if vim.api.nvim_tabpage_is_valid(original_tab) then
      vim.api.nvim_set_current_tabpage(original_tab)
    end
    if vim.api.nvim_buf_is_valid(original_buffer) then
      vim.api.nvim_buf_delete(original_buffer, { force = true })
    end

    assert.is_true(tab_still_exists)
    assert.are.equal(tab_count - 1, #vim.api.nvim_list_tabpages())
    assert.are.equal(original_buffer, current_buffer)
  end)
end)
