-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local capabilities = require("st.capabilities")
local Driver = require("st.driver")
local discovery = require("discovery")
local lifecycle = require("lifecycle")
local commands = require("commands")

local function mode_handler(mode)
  return function(driver, device)
    commands.set_mode(driver, device, { args = { mode = mode } })
  end
end

local driver = Driver("Daikin Local Heat Pump", {
  discovery = discovery.handle,
  lifecycle_handlers = {
    added = lifecycle.added,
    init = lifecycle.init,
    infoChanged = lifecycle.info_changed,
    removed = lifecycle.removed,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = commands.on,
      [capabilities.switch.commands.off.NAME] = commands.off,
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = commands.set_mode,
      [capabilities.thermostatMode.commands.off.NAME] = mode_handler("off"),
      [capabilities.thermostatMode.commands.auto.NAME] = mode_handler("auto"),
      [capabilities.thermostatMode.commands.heat.NAME] = mode_handler("heat"),
      [capabilities.thermostatMode.commands.cool.NAME] = mode_handler("cool"),
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = commands.set_heat,
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = commands.set_cool,
    },
    [capabilities.airConditionerFanMode.ID] = {
      [capabilities.airConditionerFanMode.commands.setFanMode.NAME] = commands.set_fan,
    },
    [capabilities.fanOscillationMode.ID] = {
      [capabilities.fanOscillationMode.commands.setFanOscillationMode.NAME] = commands.set_swing,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = commands.refresh,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureMeasurement,
    capabilities.thermostatMode,
    capabilities.thermostatOperatingState,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatCoolingSetpoint,
    capabilities.airConditionerFanMode,
    capabilities.fanOscillationMode,
    capabilities.refresh,
  },
  discovered_hosts = {},
  discovery_seen = {},
})

driver:run()
