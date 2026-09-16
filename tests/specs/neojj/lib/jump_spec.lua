local subject = require("neojj.lib.jump")

describe("lib.jump.translate_hunk_location", function()
  local hunk

  before_each(function()
    hunk = {
      disk_from = 10,
      index_from = 20,
      lines = {
        " context",
        "+added",
        "-removed",
        " trailing",
      },
    }
  end)

  it("returns nil when hunk is missing or offset is invalid", function()
    assert.is_nil(subject.translate_hunk_location(nil, 1))
    assert.is_nil(subject.translate_hunk_location({ disk_from = 1, index_from = 1, lines = {} }, 0))
    assert.is_nil(subject.translate_hunk_location(hunk, #hunk.lines + 1))
  end)

  it("adjusts old line numbers when additions are present", function()
    local location = subject.translate_hunk_location(hunk, 2)

    assert.are.same({
      old = 10,
      new = 21,
      line = "+added",
    }, location)
  end)

  it("adjusts new line numbers when deletions are present", function()
    local location = subject.translate_hunk_location(hunk, 3)

    assert.are.same({
      old = 11,
      new = 21,
      line = "-removed",
    }, location)
  end)
end)

describe("lib.jump.goto_file_at", function()
  it("checks paths relative to the repository root", function()
    local notification = require("neojj.lib.notification")
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "content" }, vim.fs.joinpath(root, "nested.txt"))

    local saved_jj = package.loaded["neojj.lib.jj"]
    local saved_jump = package.loaded["neojj.lib.jump"]
    package.loaded["neojj.lib.jj"] = { repo = { worktree_root = root } }
    package.loaded["neojj.lib.jump"] = nil
    local jump = require("neojj.lib.jump")

    local original_warn = notification.warn
    local opened
    local warning
    jump.open = function(_, path)
      opened = path
    end
    notification.warn = function(message)
      warning = message
    end

    jump.goto_file_at("nested.txt", { 1, 0 })
    vim.wait(100, function()
      return opened ~= nil or warning ~= nil
    end)

    notification.warn = original_warn
    package.loaded["neojj.lib.jump"] = saved_jump
    package.loaded["neojj.lib.jj"] = saved_jj
    vim.fn.delete(root, "rf")

    assert.is_nil(warning)
    assert.are.equal(vim.fs.joinpath(root, "nested.txt"), opened)
  end)
end)
