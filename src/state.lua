-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local capabilities = require("st.capabilities")
local C = require("constants")
local codec = require("codec")
local model = require("model")

local state = {}

local function emit_temperature(device, component_id, value)
  value = codec.number(value)
  if not value then return end
  local component = device.profile.components[component_id]
  device:emit_component_event(component, capabilities.temperatureMeasurement.temperature({ value = value, unit = "C" }))
end

local function thermostat_mode_event(value)
  return capabilities.thermostatMode.thermostatMode(value)
end

local function operating_event(value)
  return capabilities.thermostatOperatingState.thermostatOperatingState(value)
end

local function fan_event(value)
  return capabilities.airConditionerFanMode.fanMode(C.FAN_TO_ST[value] or "auto")
end

local function swing_event(value)
  return capabilities.fanOscillationMode.fanOscillationMode(C.SWING_TO_ST[value] or "fixed")
end

function state.emit_supported(device)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(
    { "off", "auto", "heat", "cool", "dryair", "fanonly" },
    { visibility = { displayed = false } }
  ))
  device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes(
    { "auto", "low", "medium", "high" },
    { visibility = { displayed = false } }
  ))
  device:emit_event(capabilities.fanOscillationMode.supportedFanOscillationModes(
    { "fixed", "vertical", "horizontal", "all" },
    { visibility = { displayed = false } }
  ))
end

function state.emit_all(device, control, sensor)
  local is_on = control.pow == "1"
  device:emit_event(is_on and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  device:emit_event(thermostat_mode_event(model.thermostat_mode(control)))
  device:emit_event(operating_event(model.operating_state(control, sensor)))
  device:emit_event(fan_event(control.f_rate))
  device:emit_event(swing_event(control.f_dir))

  emit_temperature(device, "main", sensor.htemp)
  emit_temperature(device, "outdoor", sensor.otemp)

  local heat = codec.number(control.dt4)
  local cool = codec.number(control.dt3)
  if heat then device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = heat, unit = "C" })) end
  if cool then device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = cool, unit = "C" })) end
  device:online()
end

return state
