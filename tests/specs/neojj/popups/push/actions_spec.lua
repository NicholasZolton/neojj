local MODULE = "neojj.popups.push.actions"

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
    local actions = require(MODULE)
    fn(actions)
  end)

  package.loaded[MODULE] = saved_subject
  for name, _ in pairs(stubs) do
    package.loaded[name] = saved[name]
  end

  assert.is_true(ok, err)
end

---@param kind string
---@param result table?
---@return table
local function new_builder(kind, result)
  local builder = {
    kind = kind,
    called = false,
    remote_value = nil,
    args_values = nil,
    target = nil,
  }

  builder.remote = function(remote)
    builder.remote_value = remote
    return builder
  end

  builder.args = function(...)
    builder.args_values = { ... }
    return builder
  end

  builder.call = function()
    builder.called = true
    return result or { code = 0, stderr = {} }
  end

  return builder
end

local function has_message(messages, needle)
  for _, msg in ipairs(messages) do
    if msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("push popup actions remote mode", function()
  it("does not prompt for remote when -r is disabled", function()
    local bookmark_builder = new_builder("bookmark")
    local finder_calls = {}
    local info_messages = {}
    local warn_messages = {}
    local remote_list_calls = 0
    local selections = { "main" }

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = {
            bookmark = function(name)
              bookmark_builder.target = name
              return bookmark_builder
            end,
            change = function()
              error("unexpected git_push.change call")
            end,
            all = new_builder("all"),
          },
          git_remote_list = {
            call = function()
              remote_list_calls = remote_list_calls + 1
              return { code = 0, stdout = { "origin git@example/repo" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function(msg)
          table.insert(info_messages, msg)
        end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function(items)
          return {
            open_async = function(_, opts)
              table.insert(finder_calls, { items = items, prompt_prefix = opts.prompt_prefix })
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return { "main", "dev" }
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return { "--dry-run" }
        end,
        get_internal_arguments = function()
          return {}
        end,
      }
      actions.push_bookmark(popup)
    end)

    assert.are.equal(0, remote_list_calls)
    assert.are.equal("main", bookmark_builder.target)
    assert.is_nil(bookmark_builder.remote_value)
    assert.is_true(bookmark_builder.called)
    assert.are.same({ "--dry-run" }, bookmark_builder.args_values)
    assert.are.equal(1, #finder_calls)
    assert.are.equal("Push bookmark", finder_calls[1].prompt_prefix)
    assert.is_true(has_message(info_messages, "Pushed bookmark main"))
    assert.is_false(has_message(warn_messages, "Push failed"))
  end)

  it("prompts for remote and applies --remote when -r is enabled", function()
    local bookmark_builder = new_builder("bookmark")
    local finder_calls = {}
    local remote_list_calls = 0
    local selections = { "main", "origin" }

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = {
            bookmark = function(name)
              bookmark_builder.target = name
              return bookmark_builder
            end,
            change = function()
              error("unexpected git_push.change call")
            end,
            all = new_builder("all"),
          },
          git_remote_list = {
            call = function()
              remote_list_calls = remote_list_calls + 1
              return { code = 0, stdout = { "upstream git@example/upstream", "origin git@example/origin" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function() end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function(items)
          return {
            open_async = function(_, opts)
              table.insert(finder_calls, { items = items, prompt_prefix = opts.prompt_prefix })
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return { "main" }
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return { remote = true }
        end,
      }
      actions.push_bookmark(popup)
    end)

    assert.are.equal(1, remote_list_calls)
    assert.is_true(bookmark_builder.called)
    assert.are.equal("origin", bookmark_builder.remote_value)
    assert.are.equal(2, #finder_calls)
    assert.are.equal("Push bookmark", finder_calls[1].prompt_prefix)
    assert.are.equal("Push remote", finder_calls[2].prompt_prefix)
    local got_remotes = finder_calls[2].items
    table.sort(got_remotes)
    assert.are.same({ "origin", "upstream" }, got_remotes)
  end)

  it("aborts push when remote picker is canceled", function()
    local bookmark_builder = new_builder("bookmark")
    local warn_messages = {}
    local selections = { "main", nil }

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = {
            bookmark = function(name)
              bookmark_builder.target = name
              return bookmark_builder
            end,
            change = function()
              error("unexpected git_push.change call")
            end,
            all = new_builder("all"),
          },
          git_remote_list = {
            call = function()
              return { code = 0, stdout = { "origin git@example/origin" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function(items)
          return {
            open_async = function(_)
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return { "main" }
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return { remote = true }
        end,
      }
      actions.push_bookmark(popup)
    end)

    assert.is_false(bookmark_builder.called)
    assert.is_true(has_message(warn_messages, "Push aborted: no remote selected"))
  end)

  it("aborts push when no remotes are configured", function()
    local bookmark_builder = new_builder("bookmark")
    local finder_calls = {}
    local warn_messages = {}
    local remote_list_calls = 0
    local selections = { "main" }

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = {
            bookmark = function(name)
              bookmark_builder.target = name
              return bookmark_builder
            end,
            change = function()
              error("unexpected git_push.change call")
            end,
            all = new_builder("all"),
          },
          git_remote_list = {
            call = function()
              remote_list_calls = remote_list_calls + 1
              return { code = 0, stdout = {} }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function(items)
          return {
            open_async = function(_, opts)
              table.insert(finder_calls, { items = items, prompt_prefix = opts.prompt_prefix })
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return { "main" }
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return { remote = true }
        end,
      }
      actions.push_bookmark(popup)
    end)

    assert.are.equal(1, remote_list_calls)
    assert.is_false(bookmark_builder.called)
    assert.are.equal(1, #finder_calls)
    assert.are.equal("Push bookmark", finder_calls[1].prompt_prefix)
    assert.is_true(has_message(warn_messages, "No remotes configured"))
  end)

  it("applies selected remote for push_all", function()
    local all_builder = new_builder("all")
    local selections = { "origin" }

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = {
            bookmark = function()
              error("unexpected git_push.bookmark call")
            end,
            change = function()
              error("unexpected git_push.change call")
            end,
            all = all_builder,
          },
          git_remote_list = {
            call = function()
              return { code = 0, stdout = { "origin git@example/origin", "upstream git@example/upstream" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function() end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          return {
            open_async = function(_)
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return { remote = true }
        end,
      }
      actions.push_all(popup)
    end)

    assert.is_true(all_builder.called)
    assert.are.equal("origin", all_builder.remote_value)
  end)

  it("pushes with no explicit source", function()
    local push_builder = new_builder("push")
    local info_messages = {}
    local remote_list_calls = 0

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = push_builder,
          git_remote_list = {
            call = function()
              remote_list_calls = remote_list_calls + 1
              return { code = 0, stdout = { "origin git@example/origin" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function(msg)
          table.insert(info_messages, msg)
        end,
        warn = function() end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          error("unexpected remote picker invocation")
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return { "--dry-run" }
        end,
        get_internal_arguments = function()
          return {}
        end,
      }
      actions.push(popup)
    end)

    assert.are.equal(0, remote_list_calls)
    assert.is_true(push_builder.called)
    assert.are.same({ "--dry-run" }, push_builder.args_values)
    assert.is_nil(push_builder.remote_value)
    assert.is_true(has_message(info_messages, "Pushed"))
  end)

  it("surfaces jj warnings when push exits 0", function()
    local push_builder = new_builder("push", {
      code = 0,
      stderr = {
        "Warning: Non-tracking remote bookmark foo@origin exists",
        "Hint: Run `jj bookmark track foo --remote=origin` to import the remote bookmark.",
        "Nothing changed.",
      },
    })
    local info_messages = {}
    local warn_messages = {}

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = push_builder,
          git_remote_list = {
            call = function()
              return { code = 0, stdout = { "origin git@example/origin" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function(msg)
          table.insert(info_messages, msg)
        end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          error("unexpected remote picker invocation")
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return {}
        end,
      }
      actions.push(popup)
    end)

    assert.is_true(push_builder.called)
    assert.is_false(has_message(info_messages, "Pushed"))
    assert.is_true(has_message(warn_messages, "with warnings"))
    assert.is_true(has_message(warn_messages, "Non-tracking remote bookmark foo@origin"))
    assert.is_true(has_message(warn_messages, "jj bookmark track foo"))
  end)

  it("captures indented continuation lines after a warning", function()
    local push_builder = new_builder("push", {
      code = 0,
      stderr = {
        "Warning: Failed to export some bookmarks:",
        "  fred@git: Ref cannot point to the root commit in Git",
        "Nothing changed.",
      },
    })
    local warn_messages = {}

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = push_builder,
          git_remote_list = {
            call = function()
              return { code = 0, stdout = {} }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          error("unexpected remote picker invocation")
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(s)
          return s
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return {}
        end,
      }
      actions.push(popup)
    end)

    assert.is_true(has_message(warn_messages, "Failed to export some bookmarks"))
    assert.is_true(has_message(warn_messages, "fred@git: Ref cannot point to the root commit"))
  end)

  it("does not flag success notifications when stderr has only status lines", function()
    local push_builder = new_builder("push", {
      code = 0,
      stderr = { "Changes to push to origin:", "  Add bookmark main" },
    })
    local info_messages = {}
    local warn_messages = {}

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = push_builder,
          git_remote_list = {
            call = function()
              return { code = 0, stdout = {} }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function(msg)
          table.insert(info_messages, msg)
        end,
        warn = function(msg)
          table.insert(warn_messages, msg)
        end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function()
          error("unexpected remote picker invocation")
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(s)
          return s
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return {}
        end,
      }
      actions.push(popup)
    end)

    assert.is_true(has_message(info_messages, "Pushed"))
    assert.is_false(has_message(warn_messages, "with warnings"))
  end)

  it("applies selected remote for plain push", function()
    local push_builder = new_builder("push")
    local selections = { "origin" }
    local finder_calls = {}
    local remote_list_calls = 0

    with_actions_module({
      ["neojj.lib.jj"] = {
        cli = {
          git_push = push_builder,
          git_remote_list = {
            call = function()
              remote_list_calls = remote_list_calls + 1
              return { code = 0, stdout = { "origin git@example/origin", "upstream git@example/upstream" } }
            end,
          },
        },
      },
      ["neojj.lib.notification"] = {
        info = function() end,
        warn = function() end,
      },
      ["neojj.buffers.fuzzy_finder"] = {
        new = function(items)
          return {
            open_async = function(_, opts)
              table.insert(finder_calls, { items = items, prompt_prefix = opts.prompt_prefix })
              return table.remove(selections, 1)
            end,
          }
        end,
      },
      ["neojj.lib.picker_cache"] = {
        get_local_bookmark_names = function()
          return {}
        end,
        get_all_revisions = function()
          return {}
        end,
        parse_selection = function(selection)
          return selection
        end,
        error_msg = function()
          return "err"
        end,
      },
    }, function(actions)
      local popup = {
        get_arguments = function()
          return {}
        end,
        get_internal_arguments = function()
          return { remote = true }
        end,
      }
      actions.push(popup)
    end)

    assert.are.equal(1, remote_list_calls)
    assert.is_true(push_builder.called)
    assert.are.equal("origin", push_builder.remote_value)
    assert.are.equal(1, #finder_calls)
    assert.are.equal("Push remote", finder_calls[1].prompt_prefix)
  end)
end)

local function with_git_executable(value, fn)
  local executable = vim.fn.executable
  vim.fn.executable = function(name)
    if name == "git" then
      return value
    end
    return executable(name)
  end

  local ok, err = pcall(fn)
  vim.fn.executable = executable
  assert.is_true(ok, err)
end

---@param opts table
---@return table<string, any>, table
local function tag_push_stubs(opts)
  local state = {
    finder_calls = {},
    info_messages = {},
    warn_messages = {},
    permission_messages = {},
    process_opts = nil,
    runner_opts = nil,
    refreshes = 0,
  }
  local selections = opts.selections or {}

  return {
    ["neojj.lib.jj"] = {
      cli = {
        git_remote_list = {
          call = function()
            return opts.remote_result or { code = 0, stdout = { "origin git@example/origin" } }
          end,
        },
      },
      repo = {
        worktree_root = "/workspace",
      },
    },
    ["neojj.watcher"] = {
      instance = function(root)
        state.refresh_root = root
        return {
          dispatch_refresh = function()
            state.refreshes = state.refreshes + 1
          end,
        }
      end,
    },
    ["neojj.lib.input"] = {
      get_permission = function(message)
        table.insert(state.permission_messages, message)
        return opts.permission ~= false
      end,
    },
    ["neojj.lib.notification"] = {
      info = function(message)
        table.insert(state.info_messages, message)
      end,
      warn = function(message)
        table.insert(state.warn_messages, message)
      end,
    },
    ["neojj.buffers.fuzzy_finder"] = {
      new = function(items)
        return {
          open_async = function(_, finder_opts)
            table.insert(state.finder_calls, { items = items, prompt_prefix = finder_opts.prompt_prefix })
            return table.remove(selections, 1)
          end,
        }
      end,
    },
    ["neojj.lib.picker_cache"] = {
      get_local_tag_names = function()
        return opts.tags or { "v1.0.0" }
      end,
      error_msg = function()
        return "remote list failed"
      end,
    },
    ["neojj.integrations.jj_backend"] = {
      colocated_git_dir = function()
        return opts.git_dir
      end,
    },
    ["neojj.process"] = {
      new = function(process_opts)
        state.process_opts = process_opts
        return process_opts
      end,
    },
    ["neojj.runner"] = {
      call = function(_, runner_opts)
        state.runner_opts = runner_opts
        return opts.push_result or { code = 0, stdout = {}, stderr = {} }
      end,
    },
  },
    state
end

describe("push popup tag actions", function()
  it("pushes selected local tag with an explicit non-deleting refspec", function()
    local stubs, state = tag_push_stubs {
      tags = { "release;candidate" },
      selections = { "release;candidate", "origin" },
      git_dir = "/primary/.git",
    }

    with_git_executable(1, function()
      with_actions_module(stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)

    assert.are.same(
      { "git", "push", "--", "origin", "refs/tags/release;candidate:refs/tags/release;candidate" },
      state.process_opts.cmd
    )
    assert.are.equal("/workspace", state.process_opts.cwd)
    assert.are.same({ GIT_DIR = "/primary/.git" }, state.process_opts.env)
    assert.is_false(state.process_opts.on_error())
    assert.are.equal("/workspace", state.refresh_root)
    assert.are.equal("Push local tag", state.finder_calls[1].prompt_prefix)
    assert.are.equal("Push remote", state.finder_calls[2].prompt_prefix)
    assert.are.equal(1, state.refreshes)
    for _, arg in ipairs(state.process_opts.cmd) do
      assert.is_nil(arg:match("^%-%-force"))
    end
  end)

  it("pushes all tags only after remote selection and confirmation", function()
    local stubs, state = tag_push_stubs {
      selections = { "origin" },
      git_dir = "/primary/.git",
    }

    with_git_executable(1, function()
      with_actions_module(stubs, function(actions)
        actions.push_all_tags {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)

    assert.are.same({ "git", "push", "--tags", "--", "origin" }, state.process_opts.cmd)
    assert.are.equal("Push remote", state.finder_calls[1].prompt_prefix)
    assert.are.same({ "Push all local tags to origin?" }, state.permission_messages)
    assert.are.equal(1, state.refreshes)
  end)

  it("rejects typed values that are not selected local tags or configured remotes", function()
    local tag_stubs, tag_state = tag_push_stubs {
      tags = { "v1.0.0" },
      selections = { "refs/tags/other" },
      git_dir = "/primary/.git",
    }
    with_git_executable(1, function()
      with_actions_module(tag_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.is_nil(tag_state.process_opts)
    assert.is_true(has_message(tag_state.warn_messages, "select a local tag"))

    local remote_stubs, remote_state = tag_push_stubs {
      selections = { "v1.0.0", "ssh://attacker.example/repo" },
      git_dir = "/primary/.git",
    }
    with_git_executable(1, function()
      with_actions_module(remote_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.is_nil(remote_state.process_opts)
    assert.is_true(has_message(remote_state.warn_messages, "select a configured remote"))
  end)

  it("does not start a tag push when tag or remote selection is canceled", function()
    local stubs, state = tag_push_stubs { selections = {}, git_dir = "/primary/.git" }

    with_git_executable(1, function()
      with_actions_module(stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)

    assert.is_nil(state.process_opts)

    local remote_stubs, remote_state = tag_push_stubs {
      selections = { "v1.0.0" },
      git_dir = "/primary/.git",
    }
    with_git_executable(1, function()
      with_actions_module(remote_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)

    assert.is_nil(remote_state.process_opts)
    assert.is_true(has_message(remote_state.warn_messages, "Push aborted: no remote selected"))
  end)

  it("does not start all-tags push when confirmation is declined", function()
    local stubs, state = tag_push_stubs {
      selections = { "origin" },
      permission = false,
      git_dir = "/primary/.git",
    }

    with_git_executable(1, function()
      with_actions_module(stubs, function(actions)
        actions.push_all_tags {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)

    assert.is_nil(state.process_opts)
    assert.are.equal(1, #state.permission_messages)
  end)

  it("rejects missing Git and non-colocated repositories before process start", function()
    local missing_stubs, missing_state = tag_push_stubs {
      selections = { "v1.0.0" },
      git_dir = "/primary/.git",
    }
    with_git_executable(0, function()
      with_actions_module(missing_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.is_nil(missing_state.process_opts)
    assert.is_true(has_message(missing_state.warn_messages, "Git executable not found"))

    local colocated_stubs, colocated_state = tag_push_stubs { selections = { "v1.0.0" } }
    with_git_executable(1, function()
      with_actions_module(colocated_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.is_nil(colocated_state.process_opts)
    assert.is_true(has_message(colocated_state.warn_messages, "requires a colocated jj/Git repository"))
  end)

  it("surfaces complete Git output and refreshes only after success", function()
    local failure_stubs, failure_state = tag_push_stubs {
      selections = { "v1.0.0", "origin" },
      git_dir = "/primary/.git",
      push_result = { code = 1, stderr = { "remote rejected" }, stdout = { "tag status" } },
    }
    with_git_executable(1, function()
      with_actions_module(failure_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.are.equal(0, failure_state.refreshes)
    assert.is_true(has_message(failure_state.warn_messages, "remote rejected\ntag status"))

    local success_stubs, success_state = tag_push_stubs {
      selections = { "v1.0.0", "origin" },
      git_dir = "/primary/.git",
    }
    with_git_executable(1, function()
      with_actions_module(success_stubs, function(actions)
        actions.push_tag {
          get_internal_arguments = function()
            return {}
          end,
        }
      end)
    end)
    assert.are.equal(1, success_state.refreshes)
    assert.are.same(false, success_state.runner_opts.hidden)
    assert.are.same(false, success_state.runner_opts.trim)
  end)
end)
