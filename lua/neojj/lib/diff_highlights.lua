local config = require("neojj.config")

local M = {}

local byte = string.byte
local sub = string.sub
local diff = vim.text.diff or vim.diff

local PLUS = byte("+")
local MINUS = byte("-")
local SPACE = byte(" ")

-- Same as delta's default: https://github.com/dandavison/delta/blob/12ef3ef0be4aebe0d2d2c810a426dbf314efa495/src/cli.rs#L594
local MAX_DISTANCE = 0.6

local diff_opts = { result_type = "indices", algorithm = "histogram" }

--- Split a string into word and non-word tokens.
---@param s string
---@return table tokens List of {start_byte, end_byte} pairs (0-indexed, end exclusive)
local function tokenize(s)
  local tokens = {}
  local i = 1
  local len = #s
  while i <= len do
    local is_word = sub(s, i, i):match("%w") ~= nil
    local j = i + 1
    while j <= len do
      if (sub(s, j, j):match("%w") ~= nil) ~= is_word then
        break
      end
      j = j + 1
    end
    tokens[#tokens + 1] = { i - 1, j - 1 }
    i = j
  end
  return tokens
end

--- Merge adjacent spans separated by one underscore or dot.
---@param spans table List of {start_byte, end_byte} pairs (0-indexed, end exclusive)
---@param s string The original string the spans index into
---@return table
local function merge_identifier_spans(spans, s)
  if #spans < 2 then
    return spans
  end

  local merged = { spans[1] }
  for i = 2, #spans do
    local previous = merged[#merged]
    local current = spans[i]
    local separator = sub(s, previous[2] + 1, previous[2] + 1)

    if current[1] - previous[2] == 1 and (separator == "_" or separator == ".") then
      merged[#merged] = { previous[1], current[2] }
    else
      merged[#merged + 1] = current
    end
  end

  return merged
end

--- Diff two strings at word granularity.
---@param old string
---@param new string
---@return table old_spans List of {start_byte, end_byte} pairs (0-indexed, end exclusive)
---@return table new_spans
---@return number distance 0.0 for identical strings, 1.0 for strings with nothing in common
function M.word_diff_spans(old, new)
  if #old + #new == 0 or old == new then
    return {}, {}, 0
  end

  local old_tokens = tokenize(old)
  local new_tokens = tokenize(new)
  local old_token_count = #old_tokens
  local new_token_count = #new_tokens
  local total_tokens = old_token_count + new_token_count

  if old_token_count == 0 or new_token_count == 0 then
    return {}, {}, 1
  end

  local old_parts = {}
  for index, token in ipairs(old_tokens) do
    old_parts[index] = sub(old, token[1] + 1, token[2])
  end

  local new_parts = {}
  for index, token in ipairs(new_tokens) do
    new_parts[index] = sub(new, token[1] + 1, token[2])
  end

  -- stylua: ignore
  local result = diff(
    table.concat(old_parts, "\n") .. "\n",
    table.concat(new_parts, "\n") .. "\n",
    diff_opts
  )

  if not result then
    return {}, {}, 0
  end

  local old_spans = {}
  local new_spans = {}
  local changed = 0

  for _, hunk in ipairs(result) do
    local deletions = hunk[2]
    local insertions = hunk[4]
    changed = changed + deletions + insertions

    if deletions > 0 and hunk[1] + deletions - 1 <= old_token_count then
      old_spans[#old_spans + 1] = {
        old_tokens[hunk[1]][1],
        old_tokens[hunk[1] + deletions - 1][2],
      }
    end
    if insertions > 0 and hunk[3] + insertions - 1 <= new_token_count then
      new_spans[#new_spans + 1] = {
        new_tokens[hunk[3]][1],
        new_tokens[hunk[3] + insertions - 1][2],
      }
    end
  end

  old_spans = merge_identifier_spans(old_spans, old)
  new_spans = merge_identifier_spans(new_spans, new)

  return old_spans, new_spans, changed / total_tokens
end

--- Apply Tree-sitter syntax and word-level highlights to diff regions in a buffer.
---@param buf Buffer
---@param regions table[]
function M.apply(buf, regions)
  local set_extmark = buf.set_extmark
  local namespace = buf:create_namespace("NeojjDiffHighlight")

  local function apply_spans(buffer_line, spans, highlight)
    for _, span in ipairs(spans) do
      set_extmark(buf, namespace, buffer_line, span[1] + 1, {
        end_col = span[2] + 1,
        hl_group = highlight,
        priority = 220,
      })
    end
  end

  for _, region in ipairs(regions) do
    local lines = buf:get_lines(region.first_line, region.last_line, false)
    local stripped = {}
    local buffer_lines = {}
    local prefixes = {}

    for index, line in ipairs(lines) do
      local prefix = byte(line, 1)
      if prefix == PLUS or prefix == MINUS or prefix == SPACE then
        stripped[#stripped + 1] = sub(line, 2)
        buffer_lines[#buffer_lines + 1] = region.first_line + index - 1
        prefixes[#prefixes + 1] = prefix
      end
    end

    if #stripped > 0 then
      if config.values.treesitter_diff_highlight then
        local filepath = region.filepath:match("-> (.+)$") or region.filepath
        local filetype = vim.filetype.match { filename = filepath }
        local language = filetype and vim.treesitter.language.get_lang(filetype)

        if language and pcall(vim.treesitter.language.inspect, language) then
          local source = table.concat(stripped, "\n")
          local parser = vim.treesitter.get_string_parser(source, language)
          parser:parse()
          parser:for_each_tree(function(tree, language_tree)
            local query = vim.treesitter.query.get(language_tree:lang(), "highlights")
            if not query then
              return
            end

            for capture_id, node in query:iter_captures(tree:root(), source) do
              local start_row, start_col, end_row, end_col = node:range()
              for row = start_row, end_row do
                local buffer_line = buffer_lines[row + 1]
                if buffer_line then
                  set_extmark(buf, namespace, buffer_line, (row == start_row and start_col or 0) + 1, {
                    end_col = (row == end_row and end_col or #stripped[row + 1]) + 1,
                    hl_group = "@" .. query.captures[capture_id],
                    priority = 210,
                  })
                end
              end
            end
          end)
        end
      end

      if config.values.word_diff_highlight then
        local index = 1
        while index <= #stripped do
          local deletion_start = index
          while index <= #stripped and prefixes[index] == MINUS do
            index = index + 1
          end

          local addition_start = index
          while index <= #stripped and prefixes[index] == PLUS do
            index = index + 1
          end

          local deletion_count = addition_start - deletion_start
          local addition_count = index - addition_start

          for offset = 0, math.min(deletion_count, addition_count) - 1 do
            local old_spans, new_spans, distance =
              M.word_diff_spans(stripped[deletion_start + offset], stripped[addition_start + offset])

            if distance <= MAX_DISTANCE then
              apply_spans(buffer_lines[deletion_start + offset], old_spans, "NeojjDiffDeleteInline")
              apply_spans(buffer_lines[addition_start + offset], new_spans, "NeojjDiffAddInline")
            end
          end

          if deletion_count == 0 and addition_count == 0 then
            index = index + 1
          end
        end
      end
    end
  end
end

return M
