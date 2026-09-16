local Spinner = require("neojj.spinner")

describe("spinner", function()
  local original_new_timer
  local original_schedule_wrap
  local original_echo
  local original_has
  local timers
  local echoes

  before_each(function()
    timers = {}
    echoes = {}
    original_new_timer = vim.uv.new_timer
    original_schedule_wrap = vim.schedule_wrap
    original_echo = vim.api.nvim_echo
    original_has = vim.fn.has
    vim.schedule_wrap = function(callback)
      return callback
    end
    vim.uv.new_timer = function()
      local timer = {
        stopped = false,
        closed = false,
      }
      function timer:start(_, _, callback)
        self.callback = callback
      end
      function timer:stop()
        self.stopped = true
      end
      function timer:is_closing()
        return self.closed
      end
      function timer:close()
        self.closed = true
      end
      table.insert(timers, timer)
      return timer
    end
    vim.api.nvim_echo = function(_, _, opts)
      table.insert(echoes, opts)
    end
  end)

  after_each(function()
    vim.uv.new_timer = original_new_timer
    vim.schedule_wrap = original_schedule_wrap
    vim.api.nvim_echo = original_echo
    vim.fn.has = original_has
  end)

  it("stops the previous spinner before starting another", function()
    local first = Spinner.new("first")
    local second = Spinner.new("second")
    first:start()
    second:start()

    assert.is_true(timers[1].stopped)
    second:stop()
  end)

  it("uses one replaceable progress message when supported", function()
    local spinner = Spinner.new("work")
    spinner:start()
    timers[1].callback()

    if original_has("nvim-0.11") == 1 then
      assert.are.equal("neojj-spinner", echoes[1].id)
      assert.are.equal("progress", echoes[1].kind)
      assert.are.equal("running", echoes[1].status)
    else
      assert.are.same({}, echoes[1])
    end
    spinner:stop()
  end)

  it("falls back to plain messages on Neovim 0.10", function()
    vim.fn.has = function(feature)
      if feature == "nvim-0.11" then
        return 0
      end
      return original_has(feature)
    end
    local spinner = Spinner.new("work")
    spinner:start()
    timers[1].callback()

    assert.are.same({}, echoes[1])
    spinner:stop()
  end)
end)
