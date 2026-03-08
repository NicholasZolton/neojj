local M = {}

local signs = { NeojjBlank = " " }

function M.get(name)
  local sign = signs[name]
  if sign == "" then
    return " "
  else
    return sign
  end
end

function M.setup(config)
  if not config.disable_signs then
    for key, val in pairs(config.signs) do
      if key == "hunk" or key == "item" or key == "section" then
        signs["NeojjClosed" .. key] = val[1]
        signs["NeojjOpen" .. key] = val[2]
      end
    end
  end
end

return M
