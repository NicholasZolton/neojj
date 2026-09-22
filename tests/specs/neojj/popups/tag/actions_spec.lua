local MODULE = "neojj.popups.tag.actions"

---@param stubs table<string, any>
---@param fn fun(actions: table)
local function with_actions_module(stubs, fn)
  local saved = {}
  for name, mod in pairs(stubs) do
    saved[name] = package.loaded[name]
    package.loaded[name] = mod
  end
  local saved_subject = package.loaded[MODULE]
  package.loaded[MODULE] = nil

  local ok, err = pcall(function()
    fn(require(MODULE))
  end)

  package.loaded[MODULE] = saved_subject
  for name, _ in pairs(stubs) do
    package.loaded[name] = saved[name]
  end
  assert.is_true(ok, err)
end

local function stubs(overrides)
  local refreshes = 0
  local values = {
    ["neojj.lib.jj"] = {
      repo = {
        worktree_root = "/workspace",
        state = { head = { change_id = "workingcopy" } },
      },
    },
    ["neojj.watcher"] = {
      instance = function(root)
        assert.are.equal("/workspace", root)
        return {
          dispatch_refresh = function()
            refreshes = refreshes + 1
          end,
        }
      end,
    },
    ["neojj.lib.jj.tag"] = {
      create = function()
        return { code = 0, stderr = {}, stdout = {} }
      end,
      move = function()
        return { code = 0, stderr = {}, stdout = {} }
      end,
      delete = function()
        return { code = 0, stderr = {}, stdout = {} }
      end,
    },
    ["neojj.lib.input"] = {
      get_user_input = function()
        return nil
      end,
      get_permission = function()
        return true
      end,
    },
    ["neojj.lib.notification"] = { info = function() end, warn = function() end },
    ["neojj.lib.picker_cache"] = {
      get_local_tag_names = function()
        return { "v1.0.0" }
      end,
      get_local_tags = function()
        return { { name = "v1.0.0", change_id = "oldtarget" } }
      end,
      get_all_revisions = function()
        return { "newtarget new description", "working new description", "root()" }
      end,
      parse_selection = function(selection)
        return selection and selection:match("^(%S+)")
      end,
    },
    ["neojj.buffers.fuzzy_finder"] = {
      new = function()
        return {
          open_async = function()
            return nil
          end,
        }
      end,
    },
  }
  for key, value in pairs(overrides or {}) do
    values[key] = value
  end
  return values, function()
    return refreshes
  end
end

describe("tag popup actions", function()
  it("creates at selected revision without allowing movement", function()
    local created_name, created_target
    local modules, refreshes = stubs {
      ["neojj.lib.input"] = {
        get_user_input = function()
          return "v1.0.0"
        end,
        get_permission = function()
          return true
        end,
      },
      ["neojj.lib.jj.tag"] = {
        create = function(name, target)
          created_name, created_target = name, target
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.create {
        get_env = function()
          return "selected"
        end,
      }
    end)

    assert.are.equal("v1.0.0", created_name)
    assert.are.equal("selected", created_target)
    assert.are.equal(1, refreshes())
  end)

  it("warns and asks before creating at working copy", function()
    local permission_message
    local modules = stubs {
      ["neojj.lib.input"] = {
        get_user_input = function()
          return "v1.0.0"
        end,
        get_permission = function(message)
          permission_message = message
          return false
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.create {
        get_env = function()
          return "@"
        end,
      }
    end)

    assert.is_truthy(permission_message:find("immutable", 1, true))
  end)

  it("warns when selected revision is the working-copy change", function()
    local permission_message
    local modules = stubs {
      ["neojj.lib.input"] = {
        get_user_input = function()
          return "v1.0.0"
        end,
        get_permission = function(message)
          permission_message = message
          return false
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.create {
        get_env = function()
          return "workingcopy"
        end,
      }
    end)

    assert.is_truthy(permission_message:find("immutable", 1, true))
  end)

  it("rejects root and blank names before creating", function()
    local created, permissions = false, 0
    local names = { "   ", "v1.0.0" }
    local modules = stubs {
      ["neojj.lib.input"] = {
        get_user_input = function()
          return table.remove(names, 1)
        end,
        get_permission = function()
          permissions = permissions + 1
          return true
        end,
      },
      ["neojj.lib.jj.tag"] = {
        create = function()
          created = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.create {
        get_env = function()
          return "selected"
        end,
      }
      actions.create {
        get_env = function()
          return "root()"
        end,
      }
    end)

    assert.is_false(created)
    assert.are.equal(0, permissions)
  end)

  it("moves only after confirmation and passes selected target", function()
    local selections = { "v1.0.0", "newtarget new description" }
    local moved_name, moved_target
    local modules, refreshes = stubs {
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function()
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.jj.tag"] = {
        move = function(name, target)
          moved_name, moved_target = name, target
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.move()
    end)

    assert.are.equal("v1.0.0", moved_name)
    assert.are.equal("newtarget", moved_target)
    assert.are.equal(1, refreshes())
  end)

  it("warns before moving to the working-copy change", function()
    local selections = { "v1.0.0", "working new description" }
    local moved, permission_message = false, nil
    local modules = stubs {
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function()
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.input"] = {
        get_user_input = function()
          return nil
        end,
        get_permission = function(message)
          permission_message = message
          return false
        end,
      },
      ["neojj.lib.jj.tag"] = {
        move = function()
          moved = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.move()
    end)

    assert.is_false(moved)
    assert.is_truthy(permission_message:find("immutable", 1, true))
  end)

  it("rejects typed revsets that are not listed revisions", function()
    local selections = { "v1.0.0", "heads(@)" }
    local moved, permissions = false, 0
    local warnings = {}
    local modules = stubs {
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function()
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.input"] = {
        get_user_input = function()
          return nil
        end,
        get_permission = function()
          permissions = permissions + 1
          return true
        end,
      },
      ["neojj.lib.jj.tag"] = {
        move = function()
          moved = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(message)
          table.insert(warnings, message)
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.move()
    end)

    assert.is_false(moved)
    assert.are.equal(0, permissions)
    assert.is_truthy(warnings[1]:find("listed revision", 1, true))
  end)

  it("rejects typed tag names that are not local tags", function()
    local selections = { "unknown", "unknown" }
    local moved, deleted = false, false
    local warnings = {}
    local modules = stubs {
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function()
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.jj.tag"] = {
        move = function()
          moved = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
        delete = function()
          deleted = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(message)
          table.insert(warnings, message)
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.move()
      actions.delete()
    end)

    assert.is_false(moved)
    assert.is_false(deleted)
    assert.are.equal(2, #warnings)
  end)

  it("rejects root before confirmation or command", function()
    local selections = { "v1.0.0", "root()" }
    local moved, permissions = false, 0
    local modules = stubs {
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function()
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.input"] = {
        get_user_input = function()
          return nil
        end,
        get_permission = function()
          permissions = permissions + 1
          return true
        end,
      },
      ["neojj.lib.jj.tag"] = {
        move = function()
          moved = true
          return { code = 0, stderr = {}, stdout = {} }
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.move()
    end)

    assert.is_false(moved)
    assert.are.equal(0, permissions)
  end)

  it("does not refresh after mutation failure and reports stderr", function()
    local warnings = {}
    local modules, refreshes = stubs {
      ["neojj.lib.input"] = {
        get_user_input = function()
          return "v1.0.0"
        end,
        get_permission = function()
          return true
        end,
      },
      ["neojj.lib.jj.tag"] = {
        create = function()
          return { code = 1, stderr = { "tag already exists" }, stdout = {} }
        end,
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(message)
          table.insert(warnings, message)
        end,
      },
    }

    with_actions_module(modules, function(actions)
      actions.create {
        get_env = function()
          return "selected"
        end,
      }
    end)

    assert.are.equal(0, refreshes())
    assert.is_truthy(warnings[1]:find("tag already exists", 1, true))
  end)
end)
