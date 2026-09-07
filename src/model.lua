-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Pure translation between the Daikin local API and SmartThings values. This
-- module never touches the SmartThings runtime, so it is fully unit tested.

local C = require("constants")
local codec = require("codec")

local model = {}

local function present(value)
  return value ~= nil and value ~= ""
end

local function numeric_or_nil(value)
  if not present(value) then return nil end
  if codec.number(value) == nil then return nil end
  return tostring(value)
end

local function is_auto(mode)
  return C.DAIKIN_TO_ST_MODE[tostring(mode or "")] == "auto"
end

--- Normalise a user supplied address. Accepts "host", "host:port" and an IPv4
--- literal, and tolerates a pasted URL. Anything else (credentials, query
--- strings, whitespace) is rejected so the driver can never be pointed at an
--- unintended HTTP target.
function model.clean_host(value)
  if type(value) ~= "string" then return nil end
  value = value:match("^%s*(.-)%s*$")
  value = value:gsub("^%a[%w+.-]*://", "")
  value = value:gsub("/.*$", "")
  if value == "" then return nil end

  local host, port = value:match("^([%w%.%-_]+):(%d+)$")
  if not host then
    host, port = value:match("^([%w%.%-_]+)$"), nil
  end
  if not host or #host > 253 then return nil end
  if port then
    local number = tonumber(port)
    if number < 1 or number > 65535 then return nil end
    return host .. ":" .. port
  end
  return host
end

function model.poll_interval(value)
  local seconds = tonumber(value) or C.DEFAULT_POLL_INTERVAL
  if seconds < C.MIN_POLL_INTERVAL then seconds = C.MIN_POLL_INTERVAL end
  if seconds > C.MAX_POLL_INTERVAL then seconds = C.MAX_POLL_INTERVAL end
  return seconds
end

--- Target temperature to send for a mode.
--- Dry and fan-only take a placeholder ("M" / "--") instead of a number.
--- Sending a number in those modes makes the adapter reject the request.
function model.setpoint_for_mode(control, mode)
  mode = tostring(mode)
  local stored = control["dt" .. mode]
  local placeholder = C.MODE_SETPOINT_PLACEHOLDER[mode]
  if placeholder then
    if present(stored) then return tostring(stored) end
    return placeholder
  end

  local candidates = {}
  local function consider(value)
    if present(value) then candidates[#candidates + 1] = value end
  end
  consider(stored)
  if is_auto(mode) then
    consider(control.dt1)
    consider(control.dt7)
  end
  consider(control.stemp)

  for _, value in ipairs(candidates) do
    local numeric = numeric_or_nil(value)
    if numeric then return numeric end
  end
  return C.DEFAULT_SETPOINT
end

--- Target humidity for a mode. The adapter keeps a stored value per mode
--- (dh1..dh7) and it may be the literal "AUTO".
function model.humidity_for_mode(control, mode)
  local stored = control["dh" .. tostring(mode)]
  if present(stored) then return tostring(stored) end
  if present(control.shum) then return tostring(control.shum) end
  return "0"
end

function model.fan_for_mode(control, mode)
  local stored = control["dfr" .. tostring(mode)]
  if present(stored) then return tostring(stored) end
  return tostring(control.f_rate or "A")
end

--- Some indoor units report the louver as two independent axes instead of the
--- combined f_dir field.
function model.uses_split_swing(control)
  return control.f_dir_ud ~= nil and control.f_dir_lr ~= nil
end

--- Current combined swing value, whichever representation the adapter uses.
function model.swing_value(control)
  if model.uses_split_swing(control) then
    local vertical = control.f_dir_ud == "S"
    local horizontal = control.f_dir_lr == "S"
    if vertical and horizontal then return "3" end
    if vertical then return "1" end
    if horizontal then return "2" end
    return "0"
  end
  return tostring(control.f_dir or "0")
end

function model.direction_for_mode(control, mode)
  local stored = control["dfd" .. tostring(mode)]
  if present(stored) then return tostring(stored) end
  return model.swing_value(control)
end

--- Build the full /aircon/set_control_info parameter list.
--- Every mandatory parameter is authoritative for the adapter, so unchanged
--- values are always read back from the current control state first.
--- Returns the ordered parameter list and a name to value lookup table.
function model.make_payload(control, changes)
  changes = changes or {}
  local mode = tostring(changes.mode or control.mode or C.MODE.HEAT)

  local params, map = {}, {}
  local function put(name, value)
    value = tostring(value)
    params[#params + 1] = { name = name, value = value }
    map[name] = value
  end

  put("pow", changes.pow or control.pow or "0")
  put("mode", mode)
  put("stemp", changes.stemp or model.setpoint_for_mode(control, mode))
  put("shum", changes.shum or model.humidity_for_mode(control, mode))

  -- Only send the optional parameters the adapter itself reports, matching the
  -- reference implementations; some indoor units reject unknown parameters.
  if changes.f_rate ~= nil or control.f_rate ~= nil then
    put("f_rate", changes.f_rate or model.fan_for_mode(control, mode))
  end

  local direction = changes.f_dir or model.direction_for_mode(control, mode)
  if model.uses_split_swing(control) then
    put("f_dir_ud", (direction == "1" or direction == "3") and "S" or "0")
    put("f_dir_lr", (direction == "2" or direction == "3") and "S" or "0")
  elseif changes.f_dir ~= nil or control.f_dir ~= nil then
    put("f_dir", direction)
  end

  return params, map
end

--- Convert a SmartThings setpoint into a Daikin temperature string.
--- SmartThings sends a bare number with no unit; values of 40 and above are
--- treated as Fahrenheit, matching the SmartThings reference drivers.
function model.normalize_setpoint(value, range)
  local number = codec.number(value)
  if number == nil then return nil end
  if number >= C.FAHRENHEIT_THRESHOLD then
    number = (number - 32) * 5 / 9
  end
  local step = C.SETPOINT_STEP
  number = math.floor(number / step + 0.5) * step
  if range then
    if number < range.min then number = range.min end
    if number > range.max then number = range.max end
  end
  return string.format("%.1f", number)
end

--- Decide which mode a setpoint change belongs to.
--- The legacy API exposes one writable setpoint that always applies to the
--- active mode, so a heating setpoint implies heat and a cooling setpoint
--- implies cool. In auto the unit has a single target temperature, which is
--- adjusted in place rather than forcing the unit out of auto.
function model.setpoint_change(control, kind, requested)
  local current = tostring(control.mode or "")
  local target_mode, range_key
  if is_auto(current) then
    target_mode, range_key = current, "auto"
  elseif kind == "heat" then
    target_mode, range_key = C.MODE.HEAT, "heat"
  else
    target_mode, range_key = C.MODE.COOL, "cool"
  end

  local setpoint = model.normalize_setpoint(requested, C.SETPOINT_RANGE[range_key])
  if not setpoint then return nil end
  return { mode = target_mode, stemp = setpoint }
end

--- Translate a SmartThings thermostat mode into a change set.
--- Selecting a mode also powers the unit on. Selecting "off" keeps the current
--- mode, because some indoor units reject a mode change combined with pow=0.
--- The adapter reports three interchangeable auto variants (0, 1 and 7); the
--- one the unit already uses is kept so it is never switched to another.
function model.mode_change(control, st_mode)
  if st_mode == "off" then return { pow = "0" } end
  local daikin_mode = C.ST_TO_DAIKIN_MODE[st_mode]
  if not daikin_mode then return nil end
  local current = tostring(control.mode or "")
  if st_mode == "auto" and is_auto(current) then daikin_mode = current end
  return { pow = "1", mode = daikin_mode }
end

function model.thermostat_mode(control)
  if control.pow ~= "1" then return "off" end
  return C.DAIKIN_TO_ST_MODE[control.mode] or "auto"
end

--- true or false when the compressor state is known, nil when it is not.
--- get_sensor_info reports 0 or the sentinel 999 while the compressor is off.
function model.compressor_running(sensor)
  local frequency = codec.number(sensor and sensor.cmpfreq)
  if frequency == nil then return nil end
  if frequency >= C.COMPRESSOR_IDLE then return false end
  return frequency > 0
end

function model.operating_state(control, sensor)
  if control.pow ~= "1" then return "idle" end
  local mode = C.DAIKIN_TO_ST_MODE[control.mode]
  if mode == "fanonly" then return "fan only" end
  if model.compressor_running(sensor) == false then return "idle" end
  if mode == "heat" then return "heating" end
  -- Dry runs the compressor to condense moisture, so "cooling" is the closest
  -- truthful SmartThings operating state.
  if mode == "cool" or mode == "dryair" then return "cooling" end
  if mode == "auto" then
    local indoor = codec.number(sensor and sensor.htemp)
    local target = codec.number(control.stemp)
    if indoor and target then
      if indoor < target then return "heating" end
      if indoor > target then return "cooling" end
    end
  end
  return "idle"
end

--- Heating and cooling setpoints to display.
--- In auto the unit has a single target temperature, so it is mirrored onto
--- both controls. That keeps the display consistent with what a setpoint
--- change actually writes while the unit is in auto.
function model.display_setpoints(control)
  local mode = tostring(control.mode or "")
  local heat = codec.number(control.dt4)
  local cool = codec.number(control.dt3)
  if is_auto(mode) then
    local target = codec.number(control.stemp)
      or codec.number(control.dt1)
      or codec.number(control.dt7)
    if target then return target, target end
  elseif mode == C.MODE.HEAT then
    heat = heat or codec.number(control.stemp)
  elseif mode == C.MODE.COOL then
    cool = cool or codec.number(control.stemp)
  end
  return heat, cool
end

return model
