-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- HTTP access to the Daikin legacy local API. Every endpoint is a plain GET
-- that answers with comma separated key=value pairs and a ret field.

local cosock = require("cosock")
local socket = require("cosock.socket")
local http = cosock.asyncify("socket.http")
local ltn12 = require("ltn12")
local log = require("log")
local C = require("constants")
local codec = require("codec")

local api = {}

local function create_socket()
  local sock = socket.tcp()
  sock:settimeout(C.REQUEST_TIMEOUT)
  return sock
end

-- Performs one request. Returns the parsed body, or nil plus a short reason.
local function request(host, path, params)
  local url = string.format("http://%s%s", host, path)
  local query = codec.query(params)
  if query ~= "" then url = url .. "?" .. query end

  local body = {}
  local _, status = http.request({
    url = url,
    method = "GET",
    headers = { Host = host, Connection = "close" },
    sink = ltn12.sink.table(body),
    create = create_socket,
  })

  if tonumber(status) ~= 200 then
    return nil, "transport: " .. codec.redact(status)
  end

  local parsed = codec.parse(table.concat(body))
  if parsed.ret ~= "OK" then
    -- ret=PARAM NG means the adapter understood the request and refused it,
    -- so retrying the same parameters cannot help.
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
