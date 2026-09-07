-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local log = require("log")
local C = require("constants")
local model = require("model")
local state = require("state")
local commands = require("commands")
local timers = require("timers")

local lifecycle = {}

--- The discovered address is persisted on the device, so polling survives a
--- driver restart without another broadcast.
local function ensure_host(driver, device)
  if device:get_field(C.FIELD_HOST) then return end
  local host = driver.discovered_hosts[device.device_network_id]
  if host then device:set_field(C.FIELD_HOST, host, { persist = true }) end
end

local function schedule(driver, device)
  local seconds = model.poll_interval(device.preferences and device.preferences.pollInterval)
  timers.set_interval(device, C.FIELD_POLL_TIMER, seconds,
    function() commands.refresh(driver, device) end, "daikin-poll")
end

local function start(driver, device)
  ensure_host(driver, device)
  state.emit_supported(device)
  schedule(driver, device)
  commands.refresh(driver, device)
end

lifecycle.added = start
lifecycle.init = start

function lifecycle.info_changed(driver, device)
  local raw = device.preferences and device.preferences.hostOverride
  if type(raw) == "string" and raw:match("%S") then
    if model.clean_host(raw) then
      log.info("Using the Daikin address configured in device settings")
    else
      log.warn("The configured Daikin address is not usable and will be ignored")
    end
  end
  schedule(driver, device)
  commands.refresh(driver, device)
end

function lifecycle.removed(driver, device)
  timers.cancel(device, C.FIELD_POLL_TIMER)
  timers.cancel(device, C.FIELD_REFRESH_TIMER)
  local network_id = device.device_network_id
  driver.discovered_hosts[network_id] = nil
  driver.discovery_seen[network_id] = nil
end

return lifecycle
