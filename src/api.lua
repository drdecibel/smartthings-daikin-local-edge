-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local cosock = require("cosock")
local socket = require("cosock.socket")
local http = cosock.asyncify("socket.http")
local ltn12 = require("ltn12")
local neturl = require("net.url")
local log = require("log")
local codec = require("codec")

local api = {}

local function get(host, path, params)
  if not host then return nil, "missing host" end
  local query = neturl.buildQuery(params or {})
  local url = string.format("http://%s%s", host, path)
  if query ~= "" then url = url .. "?" .. query end

  for attempt = 1, 2 do
    local response = {}
    local _, status = http.request({
      url = url,
      method = "GET",
      headers = { Host = host, Connection = "close" },
      sink = ltn12.sink.table(response),
      create = function()
        local sock = socket.tcp()
        sock:settimeout(4)
        return sock
      end,
    })
    if tonumber(status) == 200 then
      local parsed = codec.parse(table.concat(response))
      if parsed.ret == "OK" then return parsed end
      return nil, "Daikin returned " .. tostring(parsed.ret or "an invalid response")
    end
    log.warn(string.format("Daikin request %s failed (HTTP %s, attempt %d)", path, tostring(status), attempt))
    if attempt == 1 then socket.sleep(0.25) end
  end
  return nil, "request failed"
end

function api.basic_info(host) return get(host, "/common/basic_info") end
function api.control_info(host) return get(host, "/aircon/get_control_info") end
function api.sensor_info(host) return get(host, "/aircon/get_sensor_info") end
function api.model_info(host) return get(host, "/aircon/get_model_info") end
function api.set_control_info(host, payload) return get(host, "/aircon/set_control_info", payload) end

return api
