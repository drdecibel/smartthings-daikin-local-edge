-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Capability handlers. Every write reads the current control state first and
-- then sends back the complete parameter set, because the adapter treats each
-- mandatory parameter of set_control_info as authoritative.

local log = require("log")
local C = require("constants")
local codec = require("codec")
local api = require("api")
local model = require("model")
local state = require("state")
local timers = require("timers")
local discovery = require("discovery")

local commands = {}

local function host_for(device)
  local raw = device.preferences and device.preferences.hostOverride
  local override = model.clean_host(raw)
  if override then return override end
  if type(raw) == "string" and raw:match("%S") then
    -- info_changed already warns when the value is entered; polling every few
    -- minutes must not keep repeating it.
    log.debug("Ignoring an unusable configured Daikin address")
  end
  return device:get_field(C.FIELD_HOST)
end

local function is_adapter_refusal(reason)
  return type(reason) == "string" and reason:sub(1, 8) == "adapter:"
end

local function on_success(device)
  device:set_field(C.FIELD_FAILURES, 0)
  device:online()
end

--- Look for an adapter that moved to a different address. Only attempted once
--- the device has been unreachable for a while, and never when the owner has
--- pinned the address in the device settings.
local function maybe_relocate(driver, device)
  if model.clean_host(device.preferences and device.preferences.hostOverride) then return end
  local now = os.time()
  local last = device:get_field(C.FIELD_LAST_RELOCATE) or 0
  if now - last < C.RELOCATE_INTERVAL then return end
  device:set_field(C.FIELD_LAST_RELOCATE, now)
  discovery.relocate(driver, device)
end

local function on_problem(driver, device, reason)
  if is_adapter_refusal(reason) then
    -- The adapter answered, so it is reachable; only the request was refused.
    log.warn("Daikin refused the request (" .. tostring(reason) .. ")")
    on_success(device)
    return false
  end

  local failures = (device:get_field(C.FIELD_FAILURES) or 0) + 1
  device:set_field(C.FIELD_FAILURES, failures)
  log.warn(string.format("Daikin is not responding (%s), consecutive failures %d",
    codec.redact(reason), failures))
  if failures >= C.MAX_CONSECUTIVE_FAILURES then
    device:offline()
    maybe_relocate(driver, device)
  end
  return false
end

function commands.refresh(driver, device)
  local host = host_for(device)
  local control, control_error = api.control_info(host)
  if not control then return on_problem(driver, device, control_error) end
  local sensor, sensor_error = api.sensor_info(host)
  if not sensor then return on_problem(driver, device, sensor_error) end

  on_success(device)
  state.emit_all(device, control, sensor)
  return true
end

--- resolve is either a change table or a function that receives the current
--- control state and returns one, for commands that depend on the active mode.
local function update(driver, device, resolve)
  local host = host_for(device)
  local control, control_error = api.control_info(host)
  if not control then return on_problem(driver, device, control_error) end

  local changes = resolve
  if type(resolve) == "function" then changes = resolve(control) end
  if not changes then
    log.warn("Ignoring a Daikin command the adapter cannot carry out")
    return false
  end

  local params = model.make_payload(control, changes)
  local result, set_error = api.set_control_info(host, params)
  if not result then return on_problem(driver, device, set_error) end

  on_success(device)
  -- Read the state back so the tile shows what the unit actually accepted.
  timers.set_timeout(device, C.FIELD_REFRESH_TIMER, 1,
    function() commands.refresh(driver, device) end, "daikin-post-command")
  return true
end

function commands.on(driver, device)
  update(driver, device, { pow = "1" })
end

function commands.off(driver, device)
  update(driver, device, { pow = "0" })
end

function commands.set_mode(driver, device, command)
  local mode = command.args.mode
  update(driver, device, function(control)
    local changes = model.mode_change(control, mode)
    if not changes then
      log.warn("Unsupported thermostat mode requested: " .. tostring(mode))
    end
    return changes
  end)
end

function commands.set_heat(driver, device, command)
  update(driver, device, function(control)
    return model.setpoint_change(control, "heat", command.args.setpoint)
  end)
end

function commands.set_cool(driver, device, command)
  update(driver, device, function(control)
    return model.setpoint_change(control, "cool", command.args.setpoint)
  end)
end

function commands.set_fan(driver, device, command)
  local rate = C.ST_TO_FAN[command.args.fanMode]
  if not rate then
    log.warn("Unsupported fan mode requested: " .. tostring(command.args.fanMode))
    return
  end
  update(driver, device, { f_rate = rate })
end

function commands.set_swing(driver, device, command)
  local direction = C.ST_TO_SWING[command.args.fanOscillationMode]
  if not direction then
    log.warn("Unsupported swing mode requested: " .. tostring(command.args.fanOscillationMode))
    return
  end
  update(driver, device, { f_dir = direction })
end

return commands
