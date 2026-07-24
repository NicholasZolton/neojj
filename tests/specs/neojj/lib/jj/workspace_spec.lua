local MODULE = "neojj.lib.jj.workspace"
local harness = require("tests.util.jj_harness")

---@param stubs table<string, any>
---@param fn fun(workspace: table)
local function with_workspace_module(stubs, fn)
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

local function cli_stub(state, result)
  return {
    git_init = {
      colocate = {
        args = function(path)
          state.init_path = path
          return {
            call = function(opts)
              state.call_opts = opts
              return result
            end,
          }
        end,
      },
    },
    clear_cache = function()
      state.cache_cleared = true
    end,
    find_workspace_root = function(path)
      state.root_path = path
      return state.root
    end,
  }
end

describe("jj workspace initialization", function()
  local directory

  before_each(function()
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
  end)

  after_each(function()
    vim.fn.delete(directory, "rf")
  end)

  it("keeps the not-a-workspace error when initialization is declined", function()
    local state = {}
    local errors = {}

    with_workspace_module({
      ["neojj.lib.jj.cli"] = cli_stub(state, { code = 0 }),
      ["neojj.lib.input"] = {
        get_permission = function(message)
          state.prompt = message
          return false
        end,
      },
      ["neojj.lib.notification"] = {
        error = function(message)
          table.insert(errors, message)
        end,
      },
      ["neojj.lib.picker_cache"] = { error_msg = function() end },
    }, function(workspace)
      assert.is_nil(workspace.prompt_init(directory))
    end)

    assert.truthy(state.prompt:find("Initialize jj repository", 1, true))
    assert.is_nil(state.init_path)
    assert.truthy(errors[1]:find("is not a jj workspace", 1, true))
  end)

  it("initializes a colocated repository and returns its root", function()
    local state = { root = directory }

    with_workspace_module({
      ["neojj.lib.jj.cli"] = cli_stub(state, { code = 0 }),
      ["neojj.lib.input"] = {
        get_permission = function()
          return true
        end,
      },
      ["neojj.lib.notification"] = { error = function() end },
      ["neojj.lib.picker_cache"] = {
        error_msg = function()
          return ""
        end,
      },
    }, function(workspace)
      assert.are.equal(directory, workspace.prompt_init(directory))
    end)

    assert.are.equal(directory, state.init_path)
    assert.is_true(state.call_opts.await)
    assert.is_true(state.cache_cleared)
    assert.are.equal(directory, state.root_path)
  end)

  it("initializes a real jj repository", function()
    if not harness.jj_available() then
      pending("jj binary not available; skipping integration test")
      return
    end

    local input = require("neojj.lib.input")
    local original_get_permission = input.get_permission
    input.get_permission = function()
      return true
    end

    package.loaded[MODULE] = nil
    local ok, root = pcall(function()
      return require(MODULE).prompt_init(directory)
    end)
    input.get_permission = original_get_permission
    package.loaded[MODULE] = nil

    assert.is_true(ok, root)
    assert.are.equal(directory, root)
    assert.are.equal(1, vim.fn.isdirectory(directory .. "/.jj"))
  end)

  it("reports jj init failures without opening a workspace", function()
    local state = {}
    local errors = {}

    with_workspace_module({
      ["neojj.lib.jj.cli"] = cli_stub(state, { code = 1, stderr = { "init failed" } }),
      ["neojj.lib.input"] = {
        get_permission = function()
          return true
        end,
      },
      ["neojj.lib.notification"] = {
        error = function(message)
          table.insert(errors, message)
        end,
      },
      ["neojj.lib.picker_cache"] = {
        error_msg = function()
          return "init failed"
        end,
      },
    }, function(workspace)
      assert.is_nil(workspace.prompt_init(directory))
    end)

    assert.is_nil(state.cache_cleared)
    assert.truthy(errors[1]:find("init failed", 1, true))
  end)
end)
