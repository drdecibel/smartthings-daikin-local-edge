-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local log = require("log")
local C = require("constants")
local model = require("model")
local state = require("state")
local commands = require("commands")

local lifecycle = {}

local function cancel_timers(device)
  for timer in pairs(device.thread.timers) do device.thread:cancel_timer(timer) end
end

local function schedule(driver, device)
  cancel_timers(device)
  local seconds = model.poll_interval(device.preferences.pollInterval)
  device.thread:call_on_schedule(seconds, function() commands.refresh(driver, device) end, "Daikin polling")
end

function lifecycle.added(driver, device)
  local host = driver.discovered_hosts[device.device_network_id]
  if host then device:set_field(C.FIELD_HOST, host, { persist = true }) end
  state.emit_supported(device)
  schedule(driver, device)
  commands.refresh(driver, device)
end

function lifecycle.init(driver, device)
  state.emit_supported(device)
  schedule(driver, device)
  commands.refresh(driver, device)
end

function lifecycle.info_changed(driver, device)
  local override = model.clean_host(device.preferences.hostOverride)
  if override then
    log.info("Using configured Daikin host override")
  end
  schedule(driver, device)
  commands.refresh(driver, device)
end

function lifecycle.removed(_, device) cancel_timers(device) end

return lifecycle
