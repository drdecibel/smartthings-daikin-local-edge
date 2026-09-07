-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local socket = require("cosock.socket")
local log = require("log")
local codec = require("codec")
local C = require("constants")

local discovery = {}

local function existing(driver, network_id)
  for _, device in ipairs(driver:get_devices()) do
    if device.device_network_id == network_id then return true end
  end
  return false
end

local function create(driver, info, host)
  if info.ret ~= "OK" or info.type ~= "aircon" or not info.mac then return end
  local network_id = "daikin-" .. info.mac
  driver.discovered_hosts[network_id] = host
  if existing(driver, network_id) or driver.discovery_seen[network_id] then return end
  driver.discovery_seen[network_id] = true
  local label = codec.decode(info.name)
  if label == "" then label = "Daikin heat pump" end
  log.info("Compatible Daikin BRP069B4x discovered")
  driver:try_create_device({
    type = "LAN",
    device_network_id = network_id,
    label = label,
    profile = C.PROFILE,
    manufacturer = C.MANUFACTURER,
    model = C.MODEL,
    vendor_provided_label = "Daikin local Wi-Fi",
  })
end

local function scan_once(driver)
  local udp = socket.udp()
  udp:setoption("broadcast", true)
  udp:settimeout(4)
  local ok, err = udp:setsockname("0.0.0.0", 30000)
  if not ok then
    log.warn("Daikin discovery could not open UDP port 30000: " .. tostring(err))
    udp:close()
    return
  end
  udp:sendto("DAIKIN_UDP/common/basic_info", "255.255.255.255", 30050)
  while true do
    local body, host = udp:receivefrom()
    if not body then break end
    create(driver, codec.parse(body), host)
  end
  udp:close()
end

function discovery.handle(driver, _, should_continue)
  log.info("Starting local Daikin discovery")
  while should_continue() do scan_once(driver) end
end

return discovery
