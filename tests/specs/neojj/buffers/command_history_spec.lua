describe("command history mappings", function()
  it("reads status mappings when the buffer opens", function()
    local config = require("neojj.config")
    local Buffer = require("neojj.lib.buffer")
    local original_create = Buffer.create
    local original_module = package.loaded["neojj.buffers.command_history"]
    local original_status = vim.deepcopy(config.values.mappings.status)
    local captured

    package.loaded["neojj.buffers.command_history"] = nil
    local command_history = require("neojj.buffers.command_history")
    config.values.mappings.status["zx"] = "Close"
    Buffer.create = function(opts)
      captured = opts
      return {}
    end

    command_history:new({}):show()

    Buffer.create = original_create
    config.values.mappings.status = original_status
    package.loaded["neojj.buffers.command_history"] = original_module

    local has_custom_mapping = false
    for keys, _ in pairs(captured.mappings.n) do
      if type(keys) == "table" and vim.tbl_contains(keys, "zx") then
        has_custom_mapping = true
      end
    end
    assert.is_true(has_custom_mapping)
  end)
end)
