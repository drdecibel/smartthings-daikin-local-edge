-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local codec = {}

function codec.decode(value)
  value = value or ""
  value = value:gsub("%+", " ")
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function codec.parse(body)
  local result = {}
  if type(body) ~= "string" then return result end
  for pair in body:gmatch("[^,]+") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if key then result[codec.decode(key)] = codec.decode(value) end
  end
  return result
end

function codec.number(value)
  if value == nil or value == "" or value == "-" or value == "M" then return nil end
  return tonumber(value)
end

return codec
