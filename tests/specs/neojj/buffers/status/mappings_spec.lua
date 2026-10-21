local config = require("neojj.config")
local Status = require("neojj.buffers.status")
local Buffer = require("neojj.lib.buffer")
local Builder = require("neojj.lib.popup.builder")

describe("chunk mappings with the legacy Squash popup shortcut", function()
  local create_buffer, action, popup

  before_each(function()
    config.setup { mappings = { popup = { S = "SquashPopup" } } }
    create_buffer, action = Buffer.create, Status._action
    popup = package.loaded["neojj.lib.popup"]
  end)

  after_each(function()
    Buffer.create, Status._action = create_buffer, action
    package.loaded["neojj.lib.popup"] = popup
  end)

  it("keeps S for Squash and gS for Split in status mappings", function()
    local captured
    Buffer.create = function(opts)
      captured = opts.mappings
      return {}
    end
    Status._action = function(_, name)
      return name
    end
    Status.new(config.values, "/workspace", "/workspace"):open()

    local function bindings(mode)
      local result = {}
      for keys, command in pairs(captured[mode]) do
        for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
          if key ~= "<nop>" then
            assert.is_nil(result[key], "Duplicate status key: " .. key)
            result[key] = command
          end
        end
      end
      return result
    end

    local normal, visual = bindings("n"), bindings("v")
    assert.are.equal("n_squash_popup", normal.S)
    assert.are.equal("n_squash_popup", normal.s)
    assert.are.equal("n_split_selection", normal.gS)
    assert.are.equal("v_split_selection", visual.gS)
    assert.is_nil(visual.S)
  end)

  it("shows S as Squash and gS as Split in help without duplicate keys", function()
    package.loaded["neojj.lib.popup"] = {
      builder = function()
        return Builder.new(function(state)
          state.show = function() end
          return state
        end)
      end,
    }
    local state = require("neojj.popups.help").create { context = { section = "files" } }
    local bindings = {}
    for _, column in ipairs(state.actions) do
      for _, entry in ipairs(column) do
        for _, key in ipairs(entry.keys or {}) do
          assert.is_nil(bindings[key], "Duplicate help key: " .. key)
          bindings[key] = entry.description
        end
      end
    end
    assert.are.equal("Squash", bindings.S)
    assert.are.equal("Squash", bindings.s)
    assert.are.equal("Split selection", bindings.gS)
  end)
end)
