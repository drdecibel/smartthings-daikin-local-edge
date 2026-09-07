-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local C = require("constants")
local codec = require("codec")

local model = {}

local function usable(value)
  return codec.number(value) ~= nil
end

function model.clean_host(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  value = value:gsub("^https?://", ""):gsub("/.*$", "")
  if value == "" then return nil end
  return value
end

function model.poll_interval(value)
  local seconds = tonumber(value) or C.DEFAULT_POLL_INTERVAL
  if seconds < 60 then seconds = 60 end
  if seconds > 3600 then seconds = 3600 end
  return seconds
end

function model.setpoint_for_mode(control, mode)
  local candidates
  if mode == "4" then
    candidates = { control.dt4, control.stemp }
  elseif mode == "3" then
    candidates = { control.dt3, control.stemp }
  elseif mode == "2" then
    candidates = { control.dt2, control.stemp }
  elseif mode == "6" then
    candidates = { control.dt6, control.stemp }
  else
    candidates = { control.dt1, control.dt7, control.stemp }
  end
  for _, value in ipairs(candidates) do
    if usable(value) then return tostring(value) end
  end
  return C.DEFAULT_SETPOINT
end

function model.fan_for_mode(control, mode)
  local value = control["dfr" .. tostring(mode)]
  if value and value ~= "" then return value end
  return control.f_rate or "A"
end

function model.direction_for_mode(control, mode)
  local value = control["dfd" .. tostring(mode)]
  if value and value ~= "" then return value end
  return control.f_dir or "0"
end

function model.make_payload(control, changes)
  changes = changes or {}
  local mode = tostring(changes.mode or control.mode or C.MODE.HEAT)
  return {
    pow = tostring(changes.pow or control.pow or "0"),
    mode = mode,
    stemp = tostring(changes.stemp or model.setpoint_for_mode(control, mode)),
    shum = tostring(changes.shum or control.shum or "0"),
    f_rate = tostring(changes.f_rate or model.fan_for_mode(control, mode)),
    f_dir = tostring(changes.f_dir or model.direction_for_mode(control, mode)),
  }
end

function model.thermostat_mode(control)
  if control.pow ~= "1" then return "off" end
  return C.DAIKIN_TO_ST_MODE[control.mode] or "auto"
end

function model.operating_state(control, sensor)
  if control.pow ~= "1" then return "idle" end
  local compressor_frequency = codec.number(sensor and sensor.cmpfreq)
  if compressor_frequency ~= nil and compressor_frequency <= 0 then return "idle" end
  local mode = C.DAIKIN_TO_ST_MODE[control.mode]
  if mode == "heat" then return "heating" end
  if mode == "cool" then return "cooling" end
  if mode == "fanonly" then return "fan only" end
  return "idle"
end

return model
