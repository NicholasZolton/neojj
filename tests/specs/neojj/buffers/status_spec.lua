local config = require("neojj.config")
local harness = require("tests.util.jj_harness")
local StatusBuffer = require("neojj.buffers.status")

local function skip_if_no_jj()
  if not harness.jj_available() then
    pending("jj binary not available; skipping status buffer test")
    return true
  end
  return false
end

describe("status buffer mappings", function()
  local status
  local working_dir

  before_each(function()
    config.values = config.get_default_values()
    config.values.filewatcher.enabled = false
  end)

  after_each(function()
    if status then
      pcall(function()
        status:close()
      end)
    end
    status = nil
  end)

  it("uses configured Track and Untrack bindings from the status mapping table", function()
    if skip_if_no_jj() then
      return
    end

    config.values.mappings.status["tt"] = "Track"
    config.values.mappings.status["uu"] = "Untrack"
    config.values.mappings.status["T"] = false
    config.values.mappings.status["K"] = false

    working_dir = harness.prepare_repository { cd = true }
    status = StatusBuffer.new(config.values, working_dir, working_dir):open("replace")

    local keymaps = vim.api.nvim_buf_get_keymap(status.buffer.handle, "n")
    local lhses = {}
    for _, keymap in ipairs(keymaps) do
      lhses[keymap.lhs] = true
    end

    assert.is_true(lhses["tt"])
    assert.is_true(lhses["uu"])
    assert.is_nil(lhses["T"])
    assert.is_nil(lhses["K"])
  end)
end)
