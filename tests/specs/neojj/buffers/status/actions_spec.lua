describe("status tag popup context", function()
  local saved_popups, saved_actions
  local opened

  before_each(function()
    saved_popups = package.loaded["neojj.popups"]
    saved_actions = package.loaded["neojj.buffers.status.actions"]
    opened = {}
    package.loaded["neojj.popups"] = {
      open = function(name, callback)
        return function()
          callback(function(env)
            opened[name] = env
          end)
        end
      end,
    }
    package.loaded["neojj.buffers.status.actions"] = nil
  end)

  after_each(function()
    package.loaded["neojj.popups"] = saved_popups
    package.loaded["neojj.buffers.status.actions"] = saved_actions
  end)

  for _, case in ipairs {
    { name = "parent header", context = { kind = "change", change_id = "parent" }, expected = "parent" },
    {
      name = "working-copy header",
      context = { kind = "change", change_id = "working" },
      expected = "working",
    },
    {
      name = "bookmark",
      context = { kind = "bookmark" },
      item = { change_id = "bookmark-target" },
      expected = "bookmark-target",
    },
    {
      name = "tag",
      context = { kind = "tag" },
      item = { change_id = "tag-target" },
      expected = "tag-target",
    },
    { name = "root", context = { kind = "change", change_id = "zzzz" }, expected = "zzzz" },
    { name = "file", context = { kind = "file" }, expected = "@" },
    { name = "empty line", expected = "@" },
  } do
    it("preserves " .. case.name .. " through direct and help tag paths", function()
      local status = {
        buffer = {
          ui = {
            get_selection = function()
              error("Normal tag actions must not read stale visual selection")
            end,
            get_current_section = function()
              return nil
            end,
            get_item_under_cursor = function()
              return case.item
            end,
            context_under_cursor = function()
              return case.context
            end,
            get_commit_under_cursor = function()
              return nil
            end,
            get_yankable_under_cursor = function()
              return nil
            end,
          },
        },
      }
      local actions = require("neojj.buffers.status.actions")
      actions.n_tag_popup(status)()
      local direct_env = opened.tag
      assert.are.same({ revision = case.expected }, direct_env)

      actions.n_help_popup(status)()
      opened.tag = nil
      for _, popup in ipairs(require("neojj.popups.help.actions").popups(opened.help)) do
        if popup.name == "Tag" then
          popup.fn()
        end
      end
      assert.are.same(direct_env, opened.tag)
    end)
  end
end)
