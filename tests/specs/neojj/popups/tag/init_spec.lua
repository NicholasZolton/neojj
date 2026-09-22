local MODULE = "neojj.popups.tag"

local function with_popup_stub(fn)
  local saved_popup = package.loaded["neojj.lib.popup"]
  local saved_actions = package.loaded["neojj.popups.tag.actions"]
  local saved_subject = package.loaded[MODULE]
  local actions = {}
  local state = { actions = {} }

  package.loaded["neojj.lib.popup"] = {
    builder = function()
      local builder = {}
      function builder:name()
        return self
      end
      function builder:group_heading()
        return self
      end
      function builder:new_action_group()
        return self
      end
      function builder:action(key, description, callback, opts)
        table.insert(state.actions, {
          key = key,
          description = description,
          callback = callback,
          refresh = opts and opts.refresh,
        })
        return self
      end
      function builder:env()
        return self
      end
      function builder:build()
        return {
          show = function() end,
        }
      end
      return builder
    end,
  }
  package.loaded["neojj.popups.tag.actions"] = actions
  package.loaded[MODULE] = nil

  local ok, err = pcall(function()
    fn(require(MODULE), state)
  end)

  package.loaded[MODULE] = saved_subject
  package.loaded["neojj.popups.tag.actions"] = saved_actions
  package.loaded["neojj.lib.popup"] = saved_popup
  assert.is_true(ok, err)
end

describe("tag popup", function()
  it("delegates refresh to successful tag actions", function()
    with_popup_stub(function(tag_popup, state)
      tag_popup.create()

      assert.are.same(
        { "t", "m", "x" },
        vim.tbl_map(function(action)
          return action.key
        end, state.actions)
      )
      for _, action in ipairs(state.actions) do
        assert.is_false(action.refresh)
      end
    end)
  end)
end)
