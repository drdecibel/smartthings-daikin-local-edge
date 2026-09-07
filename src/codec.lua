-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- The Daikin local API speaks percent-encoded, comma-separated key=value
-- pairs in both directions. Everything in this module is pure Lua so that it
-- can be exercised by the unit tests without a hub.

local codec = {}

-- Matches a plain decimal number. Deliberately stricter than tonumber() so
-- that Daikin sentinels ("M", "--", "-", "AUTO") and Lua-only forms such as
-- "0x1f" or "1e3" are never mistaken for a temperature.
local NUMBER_PATTERN = "^[%-+]?%d*%.?%d+$"

local function unescape(hex)
  return string.char(tonumber(hex, 16))
end

--- Percent-decode a value. Daikin fully hex-encodes text fields such as the
--- device name; "+" is a literal plus, not a space (matching urllib.unquote).
function codec.decode(value)
  if type(value) ~= "string" then return "" end
  return (value:gsub("%%(%x%x)", unescape))
end

local function escape(char)
  return string.format("%%%02X", string.byte(char))
end

--- Percent-encode a value using the RFC 3986 unreserved set. "-" and "." are
--- unreserved, so "22.0" and "--" survive untouched.
function codec.encode(value)
  return (tostring(value):gsub("[^%w%-%.%_%~]", escape))
end

--- Build a query string from an ordered list of { name = , value = } pairs.
--- Order is preserved so requests match the documented Daikin call format.
function codec.query(params)
  local parts = {}
  for _, param in ipairs(params or {}) do
    parts[#parts + 1] = codec.encode(param.name) .. "=" .. codec.encode(param.value)
  end
  return table.concat(parts, "&")
end

--- Parse a Daikin response body into a table.
function codec.parse(body)
  local result = {}
  if type(body) ~= "string" then return result end
  for pair in body:gmatch("[^,]+") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    if key and key ~= "" then result[codec.decode(key)] = codec.decode(value) end
  end
  return result
end

--- Convert a Daikin field to a number, or nil when it is not a plain number.
function codec.number(value)
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  if not value:match(NUMBER_PATTERN) then return nil end
  return tonumber(value)
end

--- Remove anything that looks like a local address from text that is about to
--- be logged. Hub and adapter addresses must never reach the driver log.
function codec.redact(text)
  text = tostring(text or "")
  text = text:gsub("%d+%.%d+%.%d+%.%d+", "<address>")
  return text
end

return codec
