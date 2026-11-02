local Path = require("plenary.path")
local config = require("neojj.config")
local editor = require("neojj.buffers.editor")

describe("editor buffer", function()
  local events
  local group
  local tmp

  before_each(function()
    config.values = config.get_default_values()
    config.values.disable_insert_on_commit = true
    config.values.commit_editor.kind = "floating"

    events = {}
    group = vim.api.nvim_create_augroup("NeojjEditorSpec", { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "jjdescription",
      callback = function()
        table.insert(events, "jjdescription")
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "jjcommit",
      callback = function()
        table.insert(events, "jjcommit")
      end,
    })

    tmp = Path:new(vim.fn.tempname() .. ".jjdescription")
    tmp:write("summary\n\nJJ: Change ID: abc123\n", "w")
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    pcall(vim.api.nvim_buf_delete, vim.fn.bufnr(tmp:absolute()), { force = true })
    pcall(function()
      tmp:rm()
    end)
  end)

  local function open_template(contents)
    tmp:write(contents, "w")
    local instance = editor.new(tmp:absolute(), function() end, false)
    instance:open("floating")
    return instance.buffer
  end

  it("keeps empty split descriptions above the command guide", function()
    local buffer =
      open_template("JJ: Enter a description for the selected changes.\n\n\nJJ: Change ID: abc123\n")

    assert.are.same({ "", "", "JJ:", "JJ: Commands:" }, buffer:get_lines(0, 4))
    assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
    local lines = buffer:get_lines(0, -1)
    assert.are.equal("JJ: Enter a description for the selected changes.", lines[11])
    assert.are.equal("JJ: Change ID: abc123", lines[12])
  end)

  it("preserves split descriptions and highlights their summary", function()
    local buffer = open_template(
      "JJ: Enter a description for the selected changes.\nsummary\n\nbody\n\nJJ: Change ID: abc123\n"
    )

    assert.are.same({ "summary", "", "body", "", "JJ:" }, buffer:get_lines(0, 5))
    vim.cmd("syntax on")
    vim.cmd("setlocal syntax=jjdescription")
    assert.are.equal("jjdescriptionSummary", vim.fn.synIDattr(vim.fn.synID(1, 1, 1), "name"))
    assert.are.equal("jjdescriptionComment", vim.fn.synIDattr(vim.fn.synID(5, 1, 1), "name"))
  end)

  it("cycles split descriptions without treating message text as footer", function()
    local buffer = open_template(
      "JJ: Enter a description for the selected changes.\nsummary\n\nbody\n\nJJ: Change ID: abc123\n"
    )
    local original = buffer:get_lines(0, -1)
    local previous = vim.fn.maparg("<m-p>", "n", false, true).callback
    local next_message = vim.fn.maparg("<m-n>", "n", false, true).callback

    previous()
    assert.are.equal("", buffer:get_lines(0, 1)[1])
    assert.are.same(vim.list_slice(original, 5), buffer:get_lines(1, -1))
    next_message()
    assert.are.same(original, buffer:get_lines(0, -1))
  end)

  it("retains leading instructions when the template has no footer", function()
    local buffer = open_template("JJ: Instruction one\nJJ: Instruction two\nsummary\n\nbody")
    assert.are.same({ "summary", "", "body", "JJ:", "JJ: Commands:" }, buffer:get_lines(0, 5))
    assert.are.same({ "JJ: Instruction one", "JJ: Instruction two" }, buffer:get_lines(-3, -1))
  end)

  it("leaves commit description placement unchanged", function()
    local buffer = open_template("summary\n\nJJ: Change ID: abc123\n")
    assert.are.same({ "summary", "", "JJ:", "JJ: Commands:" }, buffer:get_lines(0, 4))
  end)

  it("leaves empty commit description placement unchanged", function()
    local buffer = open_template("\n\nJJ: Change ID: abc123\n")
    assert.are.same({ "", "", "JJ:", "JJ: Commands:" }, buffer:get_lines(0, 4))
  end)

  it("uses jjdescription without triggering jjcommit filetype hooks", function()
    editor.new(tmp:absolute(), function() end, false):open("floating")

    assert.are.same({ "jjdescription" }, events)
    assert.are.equal("jjdescription", vim.bo[vim.fn.bufnr(tmp:absolute())].filetype)
  end)
end)
