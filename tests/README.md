# Neojj Tests

## Running Tests

As a base requirement you must have `make` installed.

Once `make` is installed you can run tests by entering `make test` in the top level directory of Neojj into your command line.

## Adding a test dependency

If you're adding a lua plugin dependency to Neojj and wish to test it, open `tests/init.lua` in your editor.

Look for the following lines:

```lua
if os.getenv("CI") then
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  vim.cmd([[runtime! plugin/plenary.vim]])
  vim.cmd([[runtime! plugin/neojj.lua]])
else
  ensure_installed("nvim-lua/plenary.nvim")
  ensure_installed("nvim-telescope/telescope.nvim")
end
```

## Test Organization

### Where do tests go?

All tests are to be placed within the `tests/specs` directory, and placed mocking the path of the Neojj module the test is responsible for. For instance, say you wanted to test `lua/neojj/config.lua` then you would create the test file in `tests/specs/neojj/config_spec.lua` which mirrors the path in the main Neojj module.

### Where do utility functions go?

If you have any utility code that has to do with jj, it should be placed in `tests/util/jj_harness.lua`.

If you have a generic utility function _only_ relevant for tests then it should go in `tests/util/util.lua`. If it is generic enough that it could be useful in the general Neojj code then a consideration should be made to place this utility code in `lua/neojj/lib/util.lua`.

### Where should raw content files go?

Raw content files that you want to test against should go into `tests/fixtures`.

## Writing a test

Let's write a basic test to validate two things about a variable to get a quick intro to writing tests.

1. Validate the variable's type
2. Validate the variable's content

```lua
local our_variable = "Hello World!"
describe("validating a string variable", function ()
  it("should be of type string", function()
    assert.True(type(our_variable) == "string")
  end)

  it("should have content 'Hello World!'", function()
     assert.are.same("Hello World!", our_variable)
  )
end)
```

Nothing too crazy there.

Now let's take a look at a test for Neojj, specifically our `tests/specs/neojj/lib/jj/cli_spec.lua` test.

```lua
local eq = assert.are.same
local jj_harness = require("tests.util.jj_harness")
local in_prepared_repo = jj_harness.in_prepared_repo

describe("jj cli", function()
  describe("config", function()
    it(
      "can set and retrieve a config value",
      in_prepared_repo(function()
        local config = require("neojj.lib.jj.config")
        config.set("neojj.test-key", "test-value")
        local entry = config.get("neojj.test-key")
        eq("test-value", entry.value)
      end)
    )
  end)
end)
```

This test sets and retrieves a jj config value. You'll notice we're passing `in_prepared_repo` to `it`. This function sets up a simple test bed jj repository to test Neojj against. If you ever need to test Neojj in a way that requires a jj repository, you probably want to use `in_prepared_repo`.

For more test examples take a look at the tests written within the `tests` directory or our test runner's testing guide: [plenary test guide](https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md).

For the assertions available, most assertions from [`luassert`](https://github.com/lunarmodules/luassert) are accessible.
