local M = {}

local jj = require("neojj.lib.jj")
local client = require("neojj.client")
local input = require("neojj.lib.input")
local notification = require("neojj.lib.notification")

function M.new_change(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.new
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Created new change", { dismiss = true })
  else
    notification.warn("Failed to create new change", { dismiss = true })
  end
end

function M.describe(popup)
  local args = popup:get_arguments()
  local builder = jj.cli.describe
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  client.wrap(builder, {
    autocmd = "NeoJJDescribeComplete",
    msg = {
      success = "Description updated",
      fail = "Describe failed",
    },
    show_diff = true,
    interactive = true,
  })
end

function M.describe_with_message(popup)
  local msg = input.get_user_input("Describe change")
  if not msg or msg == "" then
    return
  end

  local args = popup:get_arguments()
  local builder = jj.cli.describe.no_edit.message(msg)
  if #args > 0 then
    builder = builder.args(unpack(args))
  end
  local result = builder.call()
  if result and result.code == 0 then
    notification.info("Description updated", { dismiss = true })
  else
    notification.warn("Describe failed", { dismiss = true })
  end
end

return M
