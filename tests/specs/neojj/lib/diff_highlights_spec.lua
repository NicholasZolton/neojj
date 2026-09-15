local eq = assert.are.same
local config = require("neojj.config")
local diff = require("neojj.lib.diff_highlights")

describe("word diff highlights", function()
  before_each(function()
    config.values = config.get_default_values()
  end)

  it("returns empty spans for identical strings", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("hello", "hello")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(0, distance)
  end)

  it("returns empty spans for two empty strings", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("", "")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(0, distance)
  end)

  it("reports completely different strings as unrelated", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abc", "xyz")
    eq({ { 0, 3 } }, old_spans)
    eq({ { 0, 3 } }, new_spans)
    eq(1, distance)
  end)

  it("detects a method rename with shared context", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("d.iteritems()", "d.items()")
    eq({ { 2, 11 } }, old_spans)
    eq({ { 2, 7 } }, new_spans)
    assert.is_true(distance < 0.5)
  end)

  it("detects an insertion in the middle", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("range(0, options):", "range(0, int(options)):")
    eq({ { 16, 18 } }, old_spans)
    assert.is_true(#new_spans > 0)
    assert.is_true(distance < 0.5)
  end)

  it("detects a word replacement in natural language", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("safe to read the commit number from", "safe to read build info from")
    assert.is_true(#old_spans > 0)
    assert.is_true(#new_spans > 0)
    assert.is_true(distance < 0.6)
  end)

  it("detects appended text", function()
    local old_spans, new_spans, distance =
      diff.word_diff_spans("self.table[index] =", "self.table[index] = candidates")
    eq({ { 16, 19 } }, old_spans)
    assert.is_true(#new_spans > 0)
    assert.is_true(distance < 0.5)
  end)

  it("reports unrelated lines as distant", function()
    local _, _, distance = diff.word_diff_spans(
      "#![allow(unreachable_pub)]",
      "// dead_code is a false positive here because rust will compile each integration test file as their own"
    )
    assert.is_true(distance > 0.6)
  end)

  it("handles deletion from one side only", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abcdef", "abef")
    eq({ { 0, 6 } }, old_spans)
    eq({ { 0, 4 } }, new_spans)
    eq(1, distance)
  end)

  it("handles insertion to one side only", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("abef", "abcdef")
    eq({ { 0, 4 } }, old_spans)
    eq({ { 0, 6 } }, new_spans)
    eq(1, distance)
  end)

  it("detects a single character change", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("aaa", "aba")
    eq({ { 0, 3 } }, old_spans)
    eq({ { 0, 3 } }, new_spans)
    eq(1, distance)
  end)

  it("detects moved punctuation", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("[element,]", "[element],")
    assert.is_true(#old_spans > 0 or #new_spans > 0)
    assert.is_true(distance < 0.5)
  end)

  it("handles an empty side", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("hello", "")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(1, distance)
  end)

  it("handles an empty old side", function()
    local old_spans, new_spans, distance = diff.word_diff_spans("", "hello")
    eq({}, old_spans)
    eq({}, new_spans)
    eq(1, distance)
  end)
end)

describe("diff highlight application", function()
  local function fake_buffer(lines)
    local extmarks = {}
    return {
      extmarks = extmarks,
      create_namespace = function()
        return 1
      end,
      get_lines = function()
        return lines
      end,
      set_extmark = function(_, namespace, line, column, options)
        extmarks[#extmarks + 1] = {
          namespace = namespace,
          line = line,
          column = column,
          options = options,
        }
      end,
    }
  end

  before_each(function()
    config.values = config.get_default_values()
  end)

  it("adds inline highlights to paired changed lines", function()
    local buffer = fake_buffer { "-local old_name = true", "+local new_name = true" }

    diff.apply(buffer, { { first_line = 0, last_line = 2, filepath = "example.lua" } })

    eq(2, #buffer.extmarks)
    eq("NeojjDiffDeleteInline", buffer.extmarks[1].options.hl_group)
    eq("NeojjDiffAddInline", buffer.extmarks[2].options.hl_group)
    eq(0, buffer.extmarks[1].line)
    eq(1, buffer.extmarks[2].line)
  end)

  it("maps Tree-sitter captures back onto diff lines", function()
    config.values.word_diff_highlight = false
    config.values.treesitter_diff_highlight = true
    local buffer = fake_buffer { " local value = true" }

    local original_filetype_match = vim.filetype.match
    local original_get_lang = vim.treesitter.language.get_lang
    local original_inspect = vim.treesitter.language.inspect
    local original_get_string_parser = vim.treesitter.get_string_parser
    local original_query_get = vim.treesitter.query.get

    vim.filetype.match = function()
      return "lua"
    end
    vim.treesitter.language.get_lang = function()
      return "lua"
    end
    vim.treesitter.language.inspect = function()
      return {}
    end
    vim.treesitter.get_string_parser = function()
      return {
        parse = function() end,
        for_each_tree = function(_, callback)
          callback({
            root = function()
              return {}
            end,
          }, {
            lang = function()
              return "lua"
            end,
          })
        end,
      }
    end
    vim.treesitter.query.get = function()
      local yielded = false
      return {
        captures = { "keyword" },
        iter_captures = function()
          return function()
            if yielded then
              return nil
            end
            yielded = true
            return 1,
              {
                range = function()
                  return 0, 0, 0, 5
                end,
              }
          end
        end,
      }
    end

    local success, error_message = pcall(function()
      diff.apply(buffer, { { first_line = 0, last_line = 1, filepath = "example.lua" } })
    end)

    vim.filetype.match = original_filetype_match
    vim.treesitter.language.get_lang = original_get_lang
    vim.treesitter.language.inspect = original_inspect
    vim.treesitter.get_string_parser = original_get_string_parser
    vim.treesitter.query.get = original_query_get

    assert.is_true(success, error_message)
    eq(1, #buffer.extmarks)
    eq("@keyword", buffer.extmarks[1].options.hl_group)
    eq(0, buffer.extmarks[1].line)
    eq(1, buffer.extmarks[1].column)
    eq(6, buffer.extmarks[1].options.end_col)
  end)
end)
