-- Manual integration test for jj backend
-- Run: nvim --headless -u NONE -l tests/jj_backend_test.lua

-- Add plugin to runtimepath
vim.opt.rtp:prepend(".")

-- Mock plenary modules so neojj modules can load without plenary installed
package.preload["plenary.async"] = function()
  return {
    run = function() end,
    util = { run_all = function() end },
    wrap = function(fn) return fn end,
  }
end
package.preload["plenary.path"] = function()
  local Path = {}
  Path.__index = Path
  setmetatable(Path, { __call = function(_, opts) return setmetatable(opts, Path) end })
  return Path
end

-- Stub out heavy neojj modules that cli.lua doesn't actually need for string building
-- but get pulled in through process.lua/runner.lua dependency chains
local real_require = require
local function mock_require(mod)
  -- Let our jj modules and vim builtins through
  if mod:match("^neojj%.lib%.jj") or mod:match("^neojj%.lib%.jj%.") then
    return real_require(mod)
  end
  -- Stub neojj modules that would pull in the full plugin
  if mod == "neojj.process" then
    return {
      new = function(opts)
        return {
          cmd = opts.cmd,
          cwd = opts.cwd,
          spawn_blocking = function(self)
            return { code = 1, stdout = {}, stderr = {} }
          end,
        }
      end,
    }
  end
  if mod == "neojj.runner" then
    return {
      call = function() return { code = 1, stdout = {}, stderr = {} } end,
      history = {},
    }
  end
  if mod == "neojj.logger" then
    return {
      trace = function() end,
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }
  end
  return real_require(mod)
end
rawset(_G, "require", mock_require)

local pass_count = 0
local fail_count = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    print("PASS", name)
  else
    fail_count = fail_count + 1
    print("FAIL", name .. ":", err)
  end
end

-- Test 1: Module loader
test("jj module loader", function()
  local jj = require("neojj.lib.jj")
  assert(jj ~= nil, "module should load")
end)

-- Test 2: CLI builder string representation
test("CLI builder builds commands", function()
  local cli = require("neojj.lib.jj.cli")
  local str = tostring(cli.log.no_graph.revisions("@"))
  assert(str:find("jj"), "Expected 'jj' in: " .. str)
  assert(str:find("log"), "Expected 'log' in: " .. str)
  assert(str:find("%-%-no%-graph"), "Expected '--no-graph' in: " .. str)
  assert(str:find("%-r"), "Expected '-r' in: " .. str)
end)

-- Test 3: CLI builder multi-word commands
test("CLI builder multi-word commands", function()
  local cli = require("neojj.lib.jj.cli")
  local str = tostring(cli.git_push.bookmark("main"))
  assert(str:find("git"), "Expected 'git' in: " .. str)
  assert(str:find("push"), "Expected 'push' in: " .. str)
  assert(str:find("%-%-bookmark"), "Expected '--bookmark' in: " .. str)
end)

-- Test 4: CLI builder readonly commands get --ignore-working-copy
test("CLI builder readonly flag", function()
  local cli = require("neojj.lib.jj.cli")
  local str = tostring(cli.log.no_graph)
  assert(str:find("%-%-ignore%-working%-copy"), "Expected --ignore-working-copy for log: " .. str)

  local str2 = tostring(cli.describe.message("test"))
  assert(not str2:find("%-%-ignore%-working%-copy"), "Should NOT have --ignore-working-copy for describe: " .. str2)
end)

-- Test 5: JSON parser
test("JSON parser parses concatenated objects", function()
  local log = require("neojj.lib.jj.log")
  local objects = log.parse_json_objects('{"a":1}{"b":2}{"c":3}')
  assert(#objects == 3, "Expected 3 objects, got " .. #objects)
  assert(objects[1].a == 1)
  assert(objects[2].b == 2)
  assert(objects[3].c == 3)
end)

-- Test 6: JSON parser handles strings with braces
test("JSON parser handles strings with braces", function()
  local log = require("neojj.lib.jj.log")
  local objects = log.parse_json_objects('{"msg":"hello {world}"}{"x":1}')
  assert(#objects == 2, "Expected 2 objects, got " .. #objects)
  assert(objects[1].msg == "hello {world}")
  assert(objects[2].x == 1)
end)

-- Test 7: JSON parser handles escaped quotes
test("JSON parser handles escaped quotes", function()
  local log = require("neojj.lib.jj.log")
  local objects = log.parse_json_objects('{"msg":"say \\"hi\\""}{"x":2}')
  assert(#objects == 2, "Expected 2 objects, got " .. #objects)
  assert(objects[1].msg == 'say "hi"')
end)

-- Test 8: Status parser - working copy and parent
test("Status parser parses working copy and parent", function()
  local status = require("neojj.lib.jj.status")
  local lines = {
    "Working copy changes:",
    "M hello.txt",
    "A src.lua",
    "Working copy  (@) : muvqvxnn 7809cff3 (no description set)",
    "Parent commit (@-): tvonrrpo 63990385 main | initial commit",
  }
  local parsed = status.parse_status_lines(lines)
  assert(parsed.head.change_id == "muvqvxnn", "change_id: " .. parsed.head.change_id)
  assert(parsed.head.commit_id == "7809cff3", "commit_id: " .. parsed.head.commit_id)
  assert(parsed.parent.change_id == "tvonrrpo")
  assert(parsed.parent.bookmarks[1] == "main", "bookmark: " .. vim.inspect(parsed.parent.bookmarks))
  assert(parsed.parent.description == "initial commit")
end)

-- Test 9: Status parser - diff summary
test("Status parser parses diff summary", function()
  local status = require("neojj.lib.jj.status")
  local files = status.parse_diff_summary({
    "M hello.txt",
    "A src.lua",
    "D old_file.lua",
  }, "/workspace")
  assert(#files == 3, "Expected 3 files, got " .. #files)
  assert(files[1].mode == "M")
  assert(files[1].name == "hello.txt")
  assert(files[2].mode == "A")
  assert(files[3].mode == "D")
  assert(files[3].absolute_path == "/workspace/old_file.lua")
end)

-- Test 10: Status parser - conflicts
test("Status parser parses conflicts", function()
  local status = require("neojj.lib.jj.status")
  local conflicts = status.parse_conflicts({
    "There are unresolved conflicts at these paths:",
    "  src/main.lua",
    "  src/util.lua",
    "",
    "Working copy  (@) : abc123 def456 (conflict)",
  }, "/workspace")
  assert(#conflicts == 2, "Expected 2 conflicts, got " .. #conflicts)
  assert(conflicts[1].name == "src/main.lua")
  assert(conflicts[2].name == "src/util.lua")
  assert(conflicts[1].absolute_path == "/workspace/src/main.lua")
end)

-- Test 11: Bookmark parser
test("Bookmark parser parses local and remote", function()
  local bookmark = require("neojj.lib.jj.bookmark")
  local items = bookmark.parse_list({
    "main: tvonrrpo 63990385 initial commit",
    "  @git: tvonrrpo 63990385 initial commit",
    "feature: muvqvxnn 7809cff3 wip",
  })
  assert(#items == 3, "Expected 3 items, got " .. #items)
  assert(items[1].name == "main")
  assert(items[1].remote == nil)
  assert(items[2].name == "main")
  assert(items[2].remote == "git")
  assert(items[3].name == "feature")
end)

-- Test 12: Log JSON to entry conversion
test("Log entry conversion strips trailing newline", function()
  local log = require("neojj.lib.jj.log")
  local entry = log.json_to_entry({
    change_id = "muvqvxnnyrwstlmspzqvvqzmqstxmzwq",
    commit_id = "7809cff3fa826599726c858a8c387ddc46fb7a72",
    description = "add feature\n",
    author = {
      name = "Test User",
      email = "test@example.com",
      timestamp = "2026-03-07T02:38:46-05:00",
    },
  })
  assert(entry.change_id == "muvqvxnnyrwstlmspzqvvqzmqstxmzwq")
  assert(entry.description == "add feature", "desc: " .. entry.description)
  assert(entry.author_name == "Test User")
  assert(entry.author_email == "test@example.com")
end)

-- Summary
print(string.format("\n%d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
  vim.cmd("cq1")
else
  vim.cmd("qa!")
end
