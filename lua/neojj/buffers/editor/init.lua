local Buffer = require("neojj.lib.buffer")
local config = require("neojj.config")
local util = require("neojj.lib.util")
local jj = require("neojj.lib.jj")
local logger = require("neojj.logger")
local process = require("neojj.process")

local DiffViewBuffer = require("neojj.buffers.diff")

local pad = util.pad_right

---@class EditorBuffer
---@field filename string filename of buffer
---@field on_unload function callback invoked when buffer is unloaded
---@field show_diff boolean show the diff view or not
---@field buffer Buffer
local M = {}

--- Creates a new EditorBuffer
---@param filename string the filename of buffer
---@param on_unload function the event dispatched on buffer unload
---@param show_diff boolean show the diff view or not
---@param revision? string optional revision for diff context
---@return EditorBuffer
function M.new(filename, on_unload, show_diff, revision)
  local instance = {
    show_diff = show_diff,
    filename = filename,
    on_unload = on_unload,
    revision = revision,
    buffer = nil,
  }

  setmetatable(instance, { __index = M })

  return instance
end

---Get a previous change description for message cycling
---@param index number 0-based index into recent changes
---@return string[]
local function log_message(index)
  local ok, repo = pcall(function() return jj.repo end)
  if ok and repo and repo.state and repo.state.recent then
    local items = repo.state.recent.items
    -- index is 0-based from the caller perspective, offset by 1 for past entries
    local entry = items[index + 1]
    if entry and entry.description and entry.description ~= "" then
      return vim.split(entry.description, "\n")
    end
  end
  return { "" }
end

function M:open(kind)
  assert(kind, "Editor must specify a kind")
  logger.debug("[EDITOR] Opening editor as " .. kind)

  local mapping = config.get_reversed_commit_editor_maps()
  local mapping_I = config.get_reversed_commit_editor_maps_I()
  local submitted = false

  local message_index = 1
  local message_buffer = { { "" } }
  local amend_header, footer

  local function get_log_message(index)
    return log_message(index - 2)
  end

  local function commit_message()
    return message_buffer[message_index] or get_log_message(message_index)
  end

  local function current_message(buffer)
    local message = buffer:get_lines(0, -1)
    message = util.slice(message, 1, math.max(1, #message - #footer))

    return message
  end

  self.buffer = Buffer.create {
    name = self.filename,
    filetype = "jjcommit",
    load = true,
    spell_check = config.values.commit_editor.spell_check,
    buftype = "",
    kind = kind,
    modifiable = true,
    disable_line_numbers = config.values.disable_line_numbers,
    disable_relative_line_numbers = config.values.disable_relative_line_numbers,
    status_column = not config.values.disable_signs and "" or nil,
    readonly = false,
    autocmds = {
      ["QuitPre"] = function() -- For :wq compatibility
        -- If the buffer was written (modified=false), treat :wq as submit
        if not self.buffer:get_option("modified") then
          submitted = true
          if amend_header then
            self.buffer:set_lines(0, 0, false, amend_header)
            self.buffer:write()
          end
        end

        if self.diff_view then
          self.diff_view:close()
          self.diff_view = nil
        end
      end,
    },
    on_detach = function()
      logger.debug("[EDITOR] Cleaning Up")
      if self.on_unload then
        logger.debug("[EDITOR] Running on_unload callback")
        self.on_unload(submitted and 0 or 1)
      end

      process.defer_show_preview_buffers()

      if self.diff_view then
        logger.debug("[EDITOR] Closing diff view")
        self.diff_view:close()
        self.diff_view = nil
      end

      logger.debug("[EDITOR] Done cleaning up")
    end,
    after = function(buffer)
      -- Populate help lines with mappings for buffer
      local padding = util.max_length(util.flatten(vim.tbl_values(mapping)))
      local pad_mapping = function(name)
        return pad(mapping[name] and mapping[name][1] or "<NOP>", padding)
      end

      -- jj uses "JJ:" as comment prefix in commit/describe messages
      local comment_prefix = "JJ:"
      logger.debug("[EDITOR] Using comment prefix '" .. comment_prefix .. "'")

      -- stylua: ignore
      local help_lines = {
        ("%s"):format(comment_prefix),
        ("%s Commands:"):format(comment_prefix),
        ("%s   %s Close"):format(comment_prefix, pad_mapping("Close")),
        ("%s   %s Submit"):format(comment_prefix, pad_mapping("Submit")),
        ("%s   %s Abort"):format(comment_prefix, pad_mapping("Abort")),
        ("%s   %s Previous Message"):format(comment_prefix, pad_mapping("PrevMessage")),
        ("%s   %s Next Message"):format(comment_prefix, pad_mapping("NextMessage")),
        ("%s   %s Reset Message"):format(comment_prefix, pad_mapping("ResetMessage")),
      }

      help_lines = util.filter_map(help_lines, function(line)
        if not line:match("<NOP>") then -- mapping will be <NOP> if user unbinds key
          return line
        end
      end)

      -- Find the first JJ: comment line and insert help lines before it
      local first_comment_line = vim.fn.search("^JJ:", "cnW")
      if first_comment_line > 0 then
        buffer:set_lines(first_comment_line - 1, first_comment_line - 1, false, help_lines)
      end
      buffer:write()
      buffer:move_cursor(1)

      amend_header = buffer:get_lines(0, 2)
      if amend_header[1]:match("^amend! %x+$") then
        logger.debug("[EDITOR] Found 'amend!' header")
        buffer:set_lines(0, 2, false, {}) -- remove captured header from buffer
      else
        amend_header = nil
      end

      -- Footer is the JJ: comment section (everything from the first JJ: line)
      local all_lines = buffer:get_lines(0, -1)
      local footer_start = nil
      for i, l in ipairs(all_lines) do
        if l:match("^JJ:") then
          footer_start = i
          break
        end
      end
      if footer_start then
        footer = util.slice(all_lines, footer_start, #all_lines)
      else
        footer = {}
      end

      -- Start insert mode if user has configured it
      local disable_insert = config.values.disable_insert_on_commit
      if
        (disable_insert == "auto" and vim.fn.prevnonblank(".") ~= vim.fn.line("."))
        or not disable_insert
      then
        vim.cmd(":startinsert")
      end

      -- Highlight current bookmarks if available
      local ok, repo = pcall(function() return jj.repo end)
      if ok and repo and repo.state then
        for _, bm in ipairs(repo.state.head.bookmarks or {}) do
          if bm and bm ~= "" then
            vim.fn.matchadd("NeojjBranch", vim.pesc(bm), 100)
          end
        end
      end

      local show_diff = self.show_diff
        and config.values.commit_editor.show_diff ~= false
        and kind ~= "floating"
      if show_diff then
        local diff_header = self.revision
          and ("Changes in " .. self.revision:sub(1, 8))
          or "Current Changes"
        logger.debug("[EDITOR] Opening Diffview for " .. diff_header)
        self.diff_view = DiffViewBuffer:new(diff_header, self.revision):open()
      end
    end,
    mappings = {
      i = {
        [mapping_I["Submit"]] = function(buffer)
          logger.debug("[EDITOR] Action I: Submit")
          vim.cmd.stopinsert()
          submitted = true
          if amend_header then
            buffer:set_lines(0, 0, false, amend_header)
            amend_header = nil
          end

          buffer:write()
          buffer:close(true)
        end,
        [mapping_I["Abort"]] = function(buffer)
          logger.debug("[EDITOR] Action I: Abort")
          vim.cmd.stopinsert()
          buffer:write()
          buffer:close(true)
        end,
      },
      n = {
        [mapping["Close"]] = function(buffer)
          logger.debug("[EDITOR] Action N: Close")
          buffer:write()
          buffer:close(true)
        end,
        [mapping["Submit"]] = function(buffer)
          logger.debug("[EDITOR] Action N: Submit")
          submitted = true
          if amend_header then
            buffer:set_lines(0, 0, false, amend_header)
            amend_header = nil
          end

          buffer:write()
          buffer:close(true)
        end,
        [mapping["Abort"]] = function(buffer)
          logger.debug("[EDITOR] Action N: Abort")
          buffer:write()
          buffer:close(true)
        end,
        ["ZZ"] = function(buffer)
          logger.debug("[EDITOR] Action N: ZZ (submit)")
          submitted = true
          if amend_header then
            buffer:set_lines(0, 0, false, amend_header)
            amend_header = nil
          end

          buffer:write()
          buffer:close(true)
        end,
        ["ZQ"] = function(buffer)
          logger.debug("[EDITOR] Action N: ZQ (abort)")
          buffer:write()
          buffer:close(true)
        end,
        [mapping["PrevMessage"]] = function(buffer)
          logger.debug("[EDITOR] Action N: PrevMessage")
          local message = current_message(buffer)
          message_buffer[message_index] = message

          message_index = message_index + 1

          buffer:set_lines(0, #message, false, commit_message())
          buffer:move_cursor(1)
        end,
        [mapping["NextMessage"]] = function(buffer)
          logger.debug("[EDITOR] Action N: NextMessage")
          local message = current_message(buffer)

          if message_index > 1 then
            message_buffer[message_index] = message
            message_index = message_index - 1
          end

          buffer:set_lines(0, #message, false, commit_message())
          buffer:move_cursor(1)
        end,
        [mapping["ResetMessage"]] = function(buffer)
          logger.debug("[EDITOR] Action N: ResetMessage")
          local message = current_message(buffer)
          buffer:set_lines(0, #message, false, get_log_message(message_index))
          buffer:move_cursor(1)
        end,
      },
    },
  }
end

return M
