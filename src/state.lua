-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Turns a parsed Daikin control and sensor response into SmartThings events.

local capabilities = require("st.capabilities")
local log = require("log")
local C = require("constants")
local codec = require("codec")
local model = require("model")

local state = {}

local HIDDEN = { visibility = { displayed = false } }

local function emit_temperature(device, component_id, value)
  local number = codec.number(value)
  if not number then return end
  local component = device.profile.components[component_id]
  if not component then return end
  device:emit_component_event(
    component,
    capabilities.temperatureMeasurement.temperature({ value = number, unit = "C" })
  )
end

--- Publish an optional setpoint range so the app slider matches what the
--- adapter accepts. Wrapped defensively: the range attribute is cosmetic and
--- must never be able to abort a refresh on an older hub firmware.
local function emit_range(device, capability, attribute, range)
  local ok, err = pcall(function()
    device:emit_event(capability[attribute]({
      value = { minimum = range.min, maximum = range.max, step = C.SETPOINT_STEP },
      unit = "C",
    }, HIDDEN))
  end)
  if not ok then
    log.debug("Setpoint range not published: " .. tostring(err))
  end
end

function state.emit_supported(device)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(
    C.SUPPORTED_THERMOSTAT_MODES, HIDDEN))
  device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes(
    C.SUPPORTED_FAN_MODES, HIDDEN))
  device:emit_event(capabilities.fanOscillationMode.supportedFanOscillationModes(
    C.SUPPORTED_SWING_MODES, HIDDEN))
  emit_range(device, capabilities.thermostatHeatingSetpoint,
    "heatingSetpointRange", C.SETPOINT_RANGE.heat)
  emit_range(device, capabilities.thermostatCoolingSetpoint,
    "coolingSetpointRange", C.SETPOINT_RANGE.cool)
end

local function emit_error_code(device, sensor)
  local code = sensor.err
  if code == nil then return end
  if device:get_field(C.FIELD_LAST_ERROR) == code then return end
  device:set_field(C.FIELD_LAST_ERROR, code)
  if code ~= "0" then
    log.warn("Daikin unit reports error code " .. tostring(code))
  end
end

function state.emit_all(device, control, sensor)
  local is_on = control.pow == "1"
  device:emit_event(is_on and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  device:emit_event(capabilities.thermostatMode.thermostatMode(model.thermostat_mode(control)))
  device:emit_event(capabilities.thermostatOperatingState.thermostatOperatingState(
    model.operating_state(control, sensor)))
  device:emit_event(capabilities.airConditionerFanMode.fanMode(
    C.FAN_TO_ST[control.f_rate] or "auto"))
  device:emit_event(capabilities.fanOscillationMode.fanOscillationMode(
    C.SWING_TO_ST[model.swing_value(control)] or "fixed"))

  emit_temperature(device, "main", sensor.htemp)
  emit_temperature(device, "outdoor", sensor.otemp)

  local heat, cool = model.display_setpoints(control)
  if heat then
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = heat, unit = "C" }))
  end
  if cool then
    device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = cool, unit = "C" }))
  end

  emit_error_code(device, sensor)
end

return state
