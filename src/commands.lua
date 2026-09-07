-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local capabilities = require("st.capabilities")
local log = require("log")
local C = require("constants")
local api = require("api")
local model = require("model")
local state = require("state")

local commands = {}

local function host_for(device)
  return model.clean_host(device.preferences.hostOverride) or device:get_field(C.FIELD_HOST)
end

local function refresh(_, device)
  local host = host_for(device)
  local control, control_error = api.control_info(host)
  local sensor, sensor_error = api.sensor_info(host)
  if not control or not sensor then
    log.warn(string.format("Daikin refresh failed: %s / %s", tostring(control_error), tostring(sensor_error)))
    device:offline()
    return false
  end
  state.emit_all(device, control, sensor)
  return true
end

local function update(driver, device, changes)
  local host = host_for(device)
  local control, err = api.control_info(host)
  if not control then
    log.warn("Cannot update Daikin: " .. tostring(err))
    device:offline()
    return
  end
  local payload = model.make_payload(control, changes)
  local result, set_error = api.set_control_info(host, payload)
  if not result then
    log.warn("Daikin rejected update: " .. tostring(set_error))
    device:offline()
    return
  end
  device:online()
  device.thread:call_with_delay(1, function() refresh(driver, device) end, "Daikin post-command refresh")
end

function commands.on(driver, device) update(driver, device, { pow = "1" }) end
function commands.off(driver, device) update(driver, device, { pow = "0" }) end

function commands.set_mode(driver, device, command)
  local mode = command.args.mode
  if mode == "off" then return commands.off(driver, device) end
  local daikin_mode = C.ST_TO_DAIKIN_MODE[mode]
  if not daikin_mode then
    log.warn("Unsupported thermostat mode: " .. tostring(mode))
    return
  end
  update(driver, device, { pow = "1", mode = daikin_mode })
end

function commands.set_heat(driver, device, command)
  update(driver, device, { mode = C.MODE.HEAT, stemp = tostring(command.args.setpoint) })
end

function commands.set_cool(driver, device, command)
  update(driver, device, { mode = C.MODE.COOL, stemp = tostring(command.args.setpoint) })
end

function commands.set_fan(driver, device, command)
  local rate = C.ST_TO_FAN[command.args.fanMode]
  if rate then update(driver, device, { f_rate = rate }) end
end

function commands.set_swing(driver, device, command)
  local direction = C.ST_TO_SWING[command.args.fanOscillationMode]
  if direction then update(driver, device, { f_dir = direction }) end
end

commands.refresh = refresh
return commands
