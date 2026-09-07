-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Local discovery. A single UDP broadcast to port 30050 makes every Daikin
-- adapter on the broadcast domain answer with its /common/basic_info payload.
-- The hub address is never needed, and no adapter identifier is ever logged.

local socket = require("cosock.socket")
local log = require("log")
local codec = require("codec")
local C = require("constants")

local discovery = {}

function discovery.network_id(mac)
  return "daikin-" .. tostring(mac)
end

local function open_socket()
  local udp = socket.udp()
  if not udp then return nil, "no UDP socket available" end
  udp:setoption("reuseaddr", true)
  udp:setoption("broadcast", true)
  udp:settimeout(C.DISCOVERY_TIMEOUT)

  local ok, err = udp:setsockname("0.0.0.0", C.DISCOVERY_SOURCE_PORT)
  if not ok then
    -- The adapter replies to whatever source port the request came from, so
    -- an ephemeral port works just as well when 30000 is already in use.
    log.debug("Daikin discovery is using an ephemeral source port: " .. codec.redact(err))
    ok, err = udp:setsockname("0.0.0.0", 0)
    if not ok then
      udp:close()
      return nil, err
    end
  end
  return udp
end

--- Broadcast once and call on_result(info, host) for every adapter that
--- answers, until the socket times out.
function discovery.scan(on_result)
  local udp, err = open_socket()
  if not udp then
    log.warn("Daikin discovery could not open a UDP socket: " .. codec.redact(err))
    return false
  end

  local sent, send_error = udp:sendto(C.DISCOVERY_MESSAGE, C.BROADCAST_ADDRESS, C.DISCOVERY_PORT)
  if not sent then
    log.warn("Daikin discovery broadcast failed: " .. codec.redact(send_error))
    udp:close()
    return false
  end

  while true do
    local body, host = udp:receivefrom()
    if not body or not host then break end
    local info = codec.parse(body)
    if info.ret == "OK" and info.type == "aircon" and info.mac then
      on_result(info, host)
    end
  end

  udp:close()
  return true
end

local function known_device(driver, network_id)
  for _, device in ipairs(driver:get_devices()) do
    if device.device_network_id == network_id then return true end
  end
  return false
end

local function create(driver, info, host)
  local network_id = discovery.network_id(info.mac)
  driver.discovered_hosts[network_id] = host
  if known_device(driver, network_id) or driver.discovery_seen[network_id] then return end
  driver.discovery_seen[network_id] = true

  local label = codec.decode(info.name)
  if label == "" then label = "Daikin heat pump" end

  log.info("Compatible Daikin adapter discovered")
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

function discovery.handle(driver, _, should_continue)
  log.info("Starting local Daikin discovery")
  -- Cleared per session so a deleted device can be added again without
  -- restarting the driver.
  driver.discovery_seen = {}
  while should_continue() do
    discovery.scan(function(info, host) create(driver, info, host) end)
  end
  log.info("Local Daikin discovery finished")
end

--- Look for an already known adapter that has moved to another address.
--- Returns the new address, or nil when the adapter did not answer.
function discovery.relocate(driver, device)
  local network_id = device.device_network_id
  local found
  discovery.scan(function(info, host)
    if discovery.network_id(info.mac) == network_id then found = host end
  end)
  if not found then return nil end

  driver.discovered_hosts[network_id] = found
  device:set_field(C.FIELD_HOST, found, { persist = true })
  log.info("Daikin adapter found again at a new local address")
  return found
end

return discovery
