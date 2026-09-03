local config = require("neojj.config")

local M = {}

local byte = string.byte
local sub = string.sub
local diff = vim.text.diff or vim.diff

local PLUS = byte("+")
local MINUS = byte("-")
local SPACE = byte(" ")

local MAX_DISTANCE = 0.6

local diff_opts = { result_type = "indices", algorithm = "histogram" }

---@param s string
---@return table
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

---@param spans table
---@param s string
---@return table
local function merge_underscore_spans(spans, s)
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

---@param old string
---@param new string
---@return table old_spans
---@return table new_spans
---@return number distance
function M.word_diff_spans(old, new)
  if #old + #new == 0 or old == new then
    return {}, {}, 0
  end

  local old_tokens = tokenize(old)
  local new_tokens = tokenize(new)
  local old_count = #old_tokens
  local new_count = #new_tokens
  local total_tokens = old_count + new_count

  if old_count == 0 or new_count == 0 then
    return {}, {}, 1
  end

  local old_parts = {}
  for i, token in ipairs(old_tokens) do
    old_parts[i] = sub(old, token[1] + 1, token[2])
  end

  local new_parts = {}
  for i, token in ipairs(new_tokens) do
    new_parts[i] = sub(new, token[1] + 1, token[2])
  end

  local result = diff(table.concat(old_parts, "\n") .. "\n", table.concat(new_parts, "\n") .. "\n", diff_opts)

  if not result then
    return {}, {}, 0
  end

  local old_spans = {}
  local new_spans = {}
  local changed = 0

  for _, hunk in ipairs(result) do
    local deleted = hunk[2]
    local inserted = hunk[4]
    changed = changed + deleted + inserted

    if deleted > 0 and hunk[1] + deleted - 1 <= old_count then
      old_spans[#old_spans + 1] = { old_tokens[hunk[1]][1], old_tokens[hunk[1] + deleted - 1][2] }
    end
    if inserted > 0 and hunk[3] + inserted - 1 <= new_count then
      new_spans[#new_spans + 1] = { new_tokens[hunk[3]][1], new_tokens[hunk[3] + inserted - 1][2] }
    end
  end

  old_spans = merge_underscore_spans(old_spans, old)
  new_spans = merge_underscore_spans(new_spans, new)

  return old_spans, new_spans, changed / total_tokens
end

---@param buf table
---@param regions table
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
    local count = 0

    for i, line in ipairs(lines) do
      local prefix = byte(line, 1)
      if prefix == PLUS or prefix == MINUS or prefix == SPACE then
        count = count + 1
        stripped[count] = sub(line, 2)
        buffer_lines[count] = region.first_line + i - 1
        prefixes[count] = prefix
      end
    end

    if count ~= 0 then
      if config.values.word_diff_highlight then
        local i = 1
        while i <= count do
          local delete_start = i
          while i <= count and prefixes[i] == MINUS do
            i = i + 1
          end

          local add_start = i
          while i <= count and prefixes[i] == PLUS do
            i = i + 1
          end

          local delete_count = add_start - delete_start
          local add_count = i - add_start

          for offset = 0, math.min(delete_count, add_count) - 1 do
            local old_spans, new_spans, distance =
              M.word_diff_spans(stripped[delete_start + offset], stripped[add_start + offset])

            if distance <= MAX_DISTANCE then
              apply_spans(buffer_lines[delete_start + offset], old_spans, "NeojjDiffDeleteInline")
              apply_spans(buffer_lines[add_start + offset], new_spans, "NeojjDiffAddInline")
            end
          end

          if delete_count == 0 and add_count == 0 then
            i = i + 1
          end
        end
      end
    end
  end
end

return M
