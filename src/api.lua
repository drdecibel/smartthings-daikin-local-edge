-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Access to the Daikin legacy local API. Every endpoint is a plain GET that
-- answers with comma separated key=value pairs and a ret field.

local socket = require("cosock.socket")
local log = require("log")
local C = require("constants")
local codec = require("codec")
local http = require("http")

local api = {}

-- Performs one request. Returns the parsed body, or nil plus a short reason.
local function request(host, path, params)
  local status, body = http.get(host, path, params)
  if not status then return nil, "transport: " .. tostring(body) end
  if status ~= 200 then return nil, "http " .. tostring(status) end

  local parsed = codec.parse(body)
  if parsed.ret ~= "OK" then
    -- The adapter understood the request and refused it, so retrying the same
    -- parameters cannot help.
    return nil, "adapter: " .. tostring(parsed.ret or "no ret field")
  end
  return parsed
end

local function get(host, path, params)
  if not host then return nil, "no adapter address configured" end

  local result, reason
  for attempt = 1, C.REQUEST_ATTEMPTS do
    result, reason = request(host, path, params)
    if result then return result end
    if reason:sub(1, 8) == "adapter:" then return nil, reason end
    log.warn(string.format(
      "Daikin request to %s failed (%s, attempt %d of %d)",
      path, reason, attempt, C.REQUEST_ATTEMPTS))
    if attempt < C.REQUEST_ATTEMPTS then socket.sleep(C.RETRY_DELAY) end
  end
  return nil, reason
end

function api.control_info(host)
  return get(host, "/aircon/get_control_info")
end

function api.sensor_info(host)
  return get(host, "/aircon/get_sensor_info")
end

--- params must be the ordered list produced by model.make_payload.
function api.set_control_info(host, params)
  return get(host, "/aircon/set_control_info", params)
end

return api
