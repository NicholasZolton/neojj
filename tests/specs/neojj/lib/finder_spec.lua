describe("lib.finder mini.pick integration", function()
  it("completes with nil when the picker is cancelled", function()
    local config = require("neojj.config")
    local original_check = config.check_integration
    local original_mini_pick = package.loaded["mini.pick"]
    local original_finder = package.loaded["neojj.lib.finder"]
    local selected = "not called"

    config.check_integration = function(name)
      return name == "mini_pick"
    end
    package.loaded["mini.pick"] = {
      start = function() end,
    }
    package.loaded["neojj.lib.finder"] = nil

    local finder = require("neojj.lib.finder"):new {}
    finder:add_entries { "one" }
    finder:find(function(item)
      selected = item
    end)
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniPickStop" })

    package.loaded["neojj.lib.finder"] = original_finder
    package.loaded["mini.pick"] = original_mini_pick
    config.check_integration = original_check

    assert.is_nil(selected)
  end)
end)
