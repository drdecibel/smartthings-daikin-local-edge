-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Unit tests for the parts of the driver that do not need a hub.
-- All fixtures are taken from published Daikin local API documentation and
-- contain no real device, network or account identifiers.

package.path = "./src/?.lua;" .. package.path

local codec = require("codec")
local model = require("model")
local C = require("constants")

local failures = 0
local checks = 0

local function check(label, actual, expected)
  checks = checks + 1
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL %s\n  expected: %s\n  actual:   %s",
      label, tostring(expected), tostring(actual)))
  end
end

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

-- /common/basic_info, sanitised: no real MAC, SSID or account fields.
local BASIC_INFO = "ret=OK,type=aircon,reg=EU,dst=1,ver=4_2_303,pow=0,err=0," ..
  "name=%44%61%69%6b%69%6e,icon=0,method=home only,port=30050,id=,pw=," ..
  "adp_kind=3,pv=3,cpv=2,cpv_minor=00,mac=AABBCCDDEEFF,adp_mode=run,en_hol=0"

-- /aircon/get_control_info while the unit sits in cool mode, powered off.
local CONTROL_COOL = "ret=OK,pow=0,mode=3,adv=,stemp=25.0,shum=0," ..
  "dt1=25.0,dt2=M,dt3=25.0,dt4=22.0,dt5=25.0,dt7=25.0," ..
  "dh1=AUTO,dh2=50,dh3=0,dh4=0,dh5=0,dh7=AUTO,dhh=50," ..
  "b_mode=3,b_stemp=25.0,b_shum=0,alert=255,f_rate=7,f_dir=1,b_f_rate=7,b_f_dir=1," ..
  "dfr1=5,dfr2=5,dfr3=7,dfr4=5,dfr5=5,dfr6=5,dfr7=5,dfrh=5," ..
  "dfd1=0,dfd2=0,dfd3=1,dfd4=0,dfd5=0,dfd6=0,dfd7=0,dfdh=0"

-- /aircon/get_sensor_info with the documented idle compressor sentinel.
local SENSOR_IDLE = "ret=OK,htemp=24.0,hhum=-,otemp=15.0,err=0,cmpfreq=999"
local SENSOR_RUNNING = "ret=OK,htemp=20.0,hhum=45,otemp=-3.0,err=0,cmpfreq=42"

local basic = codec.parse(BASIC_INFO)
local control = codec.parse(CONTROL_COOL)
local sensor_idle = codec.parse(SENSOR_IDLE)
local sensor_running = codec.parse(SENSOR_RUNNING)

local function query(params)
  return codec.query(params)
end

--------------------------------------------------------------------------
-- codec
--------------------------------------------------------------------------

check("basic_info ret", basic.ret, "OK")
check("basic_info name is percent decoded", basic.name, "Daikin")
check("basic_info adapter kind", basic.adp_kind, "3")
check("value containing spaces survives", basic.method, "home only")
-- Daikin fully hex encodes text, so "+" is a literal plus (urllib.unquote).
check("plus is literal", codec.decode("Living+room"), "Living+room")
check("encoded space", codec.decode("Living%20room"), "Living room")
check("decode of nil is empty", codec.decode(nil), "")

check("encode keeps unreserved", codec.encode("22.0"), "22.0")
check("encode keeps placeholder", codec.encode("--"), "--")
check("encode escapes space", codec.encode("a b"), "a%20b")
check("encode escapes ampersand", codec.encode("a&b"), "a%26b")
check("query preserves order",
  query({ { name = "pow", value = "1" }, { name = "mode", value = "3" } }),
  "pow=1&mode=3")
check("query of nothing", query({}), "")

check("number parses decimal", codec.number("22.5"), 22.5)
check("number parses negative", codec.number("-3.0"), -3.0)
check("number rejects dry placeholder", codec.number("M"), nil)
check("number rejects dash", codec.number("-"), nil)
check("number rejects double dash", codec.number("--"), nil)
check("number rejects AUTO", codec.number("AUTO"), nil)
check("number rejects hex", codec.number("0x1f"), nil)
check("number rejects exponent", codec.number("1e3"), nil)
check("number rejects nil", codec.number(nil), nil)

check("redact hides addresses",
  codec.redact("connect to 192.0.2.10 failed"), "connect to <address> failed")

--------------------------------------------------------------------------
-- Host handling
--------------------------------------------------------------------------

check("host from pasted url",
  model.clean_host(" http://192.0.2.10/aircon/get_sensor_info "), "192.0.2.10")
check("plain host name", model.clean_host("heatpump.lan"), "heatpump.lan")
check("host with port", model.clean_host("192.0.2.10:8080"), "192.0.2.10:8080")
check("empty host", model.clean_host(""), nil)
check("blank host", model.clean_host("   "), nil)
check("credentials rejected", model.clean_host("http://user:secret@example.com/"), nil)
check("query string rejected", model.clean_host("example.com?a=b"), nil)
check("space rejected", model.clean_host("a b"), nil)
check("bad port rejected", model.clean_host("192.0.2.10:99999"), nil)
check("non string rejected", model.clean_host(nil), nil)

check("poll interval default", model.poll_interval(nil), C.DEFAULT_POLL_INTERVAL)
check("poll interval from string", model.poll_interval("600"), 600)
check("poll interval floor", model.poll_interval("5"), C.MIN_POLL_INTERVAL)
check("poll interval ceiling", model.poll_interval("100000"), C.MAX_POLL_INTERVAL)

--------------------------------------------------------------------------
-- Per mode control values
--------------------------------------------------------------------------

check("heat setpoint from dt4", model.setpoint_for_mode(control, C.MODE.HEAT), "22.0")
check("cool setpoint from dt3", model.setpoint_for_mode(control, C.MODE.COOL), "25.0")
check("dry setpoint placeholder", model.setpoint_for_mode(control, C.MODE.DRY), "M")
-- The fixture has no dt6, which matches adapters that omit it entirely.
check("fan setpoint placeholder", model.setpoint_for_mode(control, C.MODE.FAN), "--")
check("auto setpoint from dt1", model.setpoint_for_mode(control, C.MODE.AUTO), "25.0")
check("setpoint falls back to default",
  model.setpoint_for_mode({ mode = "4", stemp = "M" }, C.MODE.HEAT), C.DEFAULT_SETPOINT)

check("humidity from dh1", model.humidity_for_mode(control, C.MODE.AUTO_1), "AUTO")
check("humidity from dh3", model.humidity_for_mode(control, C.MODE.COOL), "0")
check("humidity from dh2", model.humidity_for_mode(control, C.MODE.DRY), "50")
check("humidity falls back to shum", model.humidity_for_mode(control, C.MODE.FAN), "0")

check("fan rate from dfr3", model.fan_for_mode(control, C.MODE.COOL), "7")
check("fan rate from dfr6", model.fan_for_mode(control, C.MODE.FAN), "5")
check("fan rate falls back", model.fan_for_mode({ f_rate = "B" }, C.MODE.HEAT), "B")

check("direction from dfd3", model.direction_for_mode(control, C.MODE.COOL), "1")
check("direction falls back", model.direction_for_mode({ f_dir = "3" }, C.MODE.HEAT), "3")

--------------------------------------------------------------------------
-- set_control_info payloads
--------------------------------------------------------------------------

check("power on keeps every current setting",
  query((model.make_payload(control, { pow = "1" }))),
  "pow=1&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=1")

check("power off keeps the current mode",
  query((model.make_payload(control, { pow = "0" }))),
  "pow=0&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=1")

check("switching to heat restores the stored heat settings",
  query((model.make_payload(control, { pow = "1", mode = C.MODE.HEAT }))),
  "pow=1&mode=4&stemp=22.0&shum=0&f_rate=5&f_dir=0")

-- Dry mode must send the placeholder temperature and the stored dry humidity.
check("switching to dry sends the placeholder temperature",
  query((model.make_payload(control, { pow = "1", mode = C.MODE.DRY }))),
  "pow=1&mode=2&stemp=M&shum=50&f_rate=5&f_dir=0")

check("switching to fan only sends the placeholder temperature",
  query((model.make_payload(control, { pow = "1", mode = C.MODE.FAN }))),
  "pow=1&mode=6&stemp=--&shum=0&f_rate=5&f_dir=0")

check("changing the fan rate preserves everything else",
  query((model.make_payload(control, { f_rate = "A" }))),
  "pow=0&mode=3&stemp=25.0&shum=0&f_rate=A&f_dir=1")

check("changing the swing preserves everything else",
  query((model.make_payload(control, { f_dir = "3" }))),
  "pow=0&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=3")

local _, payload_map = model.make_payload(control, { pow = "1" })
check("payload lookup table", payload_map.stemp, "25.0")

-- An adapter that reports neither f_rate nor f_dir must not be sent them.
local minimal = codec.parse("ret=OK,pow=1,mode=4,stemp=21.0,shum=0,dt4=21.0")
check("optional parameters are omitted when unsupported",
  query((model.make_payload(minimal, { pow = "0" }))),
  "pow=0&mode=4&stemp=21.0&shum=0")

--------------------------------------------------------------------------
-- Split swing adapters (separate up/down and left/right louvers)
--------------------------------------------------------------------------

local split = codec.parse("ret=OK,pow=1,mode=4,stemp=21.0,shum=0,dt4=21.0," ..
  "f_rate=A,f_dir_ud=S,f_dir_lr=0")

check("split swing detected", model.uses_split_swing(split), true)
check("split swing vertical", model.swing_value(split), "1")
check("split swing both", model.swing_value(
  { f_dir_ud = "S", f_dir_lr = "S" }), "3")
check("split swing horizontal", model.swing_value(
  { f_dir_ud = "0", f_dir_lr = "S" }), "2")
check("split swing off", model.swing_value(
  { f_dir_ud = "0", f_dir_lr = "0" }), "0")
check("combined swing still works", model.swing_value(control), "1")

check("split swing is written back as two axes",
  query((model.make_payload(split, { f_dir = "3" }))),
  "pow=1&mode=4&stemp=21.0&shum=0&f_rate=A&f_dir_ud=S&f_dir_lr=S")

check("split swing preserved when changing the fan rate",
  query((model.make_payload(split, { f_rate = "5" }))),
  "pow=1&mode=4&stemp=21.0&shum=0&f_rate=5&f_dir_ud=S&f_dir_lr=0")

--------------------------------------------------------------------------
-- Setpoint normalisation
--------------------------------------------------------------------------

check("celsius setpoint", model.normalize_setpoint(22, C.SETPOINT_RANGE.heat), "22.0")
check("half degree step", model.normalize_setpoint(22.3, C.SETPOINT_RANGE.heat), "22.5")
check("rounds down to the step", model.normalize_setpoint(22.2, C.SETPOINT_RANGE.heat), "22.0")
-- SmartThings sends no unit, so a Fahrenheit location sends 72 for 22 C.
check("fahrenheit is converted", model.normalize_setpoint(72, C.SETPOINT_RANGE.heat), "22.0")
check("heat setpoint clamped low", model.normalize_setpoint(2, C.SETPOINT_RANGE.heat), "10.0")
check("heat setpoint clamped high", model.normalize_setpoint(39, C.SETPOINT_RANGE.heat), "31.0")
check("cool setpoint clamped low", model.normalize_setpoint(12, C.SETPOINT_RANGE.cool), "18.0")
check("rejects a non number", model.normalize_setpoint("warm", C.SETPOINT_RANGE.heat), nil)

local heat_change = model.setpoint_change(control, "heat", 21)
check("heating setpoint selects heat mode", heat_change.mode, C.MODE.HEAT)
check("heating setpoint value", heat_change.stemp, "21.0")
check("heating setpoint does not power the unit on",
  query((model.make_payload(control, heat_change))),
  "pow=0&mode=4&stemp=21.0&shum=0&f_rate=5&f_dir=0")

local cool_change = model.setpoint_change(control, "cool", 24)
check("cooling setpoint selects cool mode", cool_change.mode, C.MODE.COOL)
check("cooling setpoint value", cool_change.stemp, "24.0")

-- In auto the unit has a single target temperature, so it is adjusted in place.
local auto_control = codec.parse("ret=OK,pow=1,mode=7,stemp=23.0,shum=0,dt7=23.0," ..
  "dh7=AUTO,f_rate=A,f_dir=0,dfr7=A,dfd7=0")
local auto_change = model.setpoint_change(auto_control, "heat", 24)
check("auto keeps its own mode", auto_change.mode, "7")
check("auto setpoint value", auto_change.stemp, "24.0")

--------------------------------------------------------------------------
-- Mode changes
--------------------------------------------------------------------------

check("selecting heat powers on", model.mode_change(control, "heat").pow, "1")
check("selecting heat sets mode 4", model.mode_change(control, "heat").mode, C.MODE.HEAT)
check("selecting off keeps the mode", model.mode_change(control, "off").mode, nil)
check("selecting off powers down", model.mode_change(control, "off").pow, "0")
check("off request keeps the current mode on the wire",
  query((model.make_payload(control, model.mode_change(control, "off")))),
  "pow=0&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=1")
check("auto keeps the adapter auto variant",
  model.mode_change(auto_control, "auto").mode, "7")
check("auto from cool uses mode 0", model.mode_change(control, "auto").mode, C.MODE.AUTO)
check("unknown mode is refused", model.mode_change(control, "eco"), nil)

--------------------------------------------------------------------------
-- Reported state
--------------------------------------------------------------------------

check("powered off reports off", model.thermostat_mode(control), "off")
local running = codec.parse(CONTROL_COOL)
running.pow = "1"
running.mode = C.MODE.HEAT
check("heat mode reported", model.thermostat_mode(running), "heat")

check("idle sentinel is not a running compressor",
  model.compressor_running(sensor_idle), false)
check("running compressor", model.compressor_running(sensor_running), true)
check("zero is not running", model.compressor_running({ cmpfreq = "0" }), false)
check("missing compressor data is unknown", model.compressor_running({}), nil)

check("off unit is idle", model.operating_state(control, sensor_running), "idle")
check("idle sentinel reports idle", model.operating_state(running, sensor_idle), "idle")
check("heating while the compressor runs",
  model.operating_state(running, sensor_running), "heating")

local cooling = codec.parse(CONTROL_COOL)
cooling.pow = "1"
check("cooling while the compressor runs",
  model.operating_state(cooling, sensor_running), "cooling")

local drying = codec.parse(CONTROL_COOL)
drying.pow = "1"
drying.mode = C.MODE.DRY
check("dry is reported as cooling",
  model.operating_state(drying, sensor_running), "cooling")

local fanning = codec.parse(CONTROL_COOL)
fanning.pow = "1"
fanning.mode = C.MODE.FAN
check("fan only never depends on the compressor",
  model.operating_state(fanning, sensor_idle), "fan only")

local auto_running = codec.parse("ret=OK,pow=1,mode=1,stemp=23.0,shum=0,f_rate=A,f_dir=0")
check("auto below target is heating",
  model.operating_state(auto_running, sensor_running), "heating")
check("auto above target is cooling",
  model.operating_state(auto_running, { htemp = "26.0", cmpfreq = "42" }), "cooling")
check("auto at target is idle",
  model.operating_state(auto_running, { htemp = "23.0", cmpfreq = "42" }), "idle")
check("unknown compressor state still follows the mode",
  model.operating_state(running, {}), "heating")

--------------------------------------------------------------------------
-- Displayed setpoints
--------------------------------------------------------------------------

local heat_display, cool_display = model.display_setpoints(control)
check("displayed heating setpoint", heat_display, 22.0)
check("displayed cooling setpoint", cool_display, 25.0)

local auto_heat, auto_cool = model.display_setpoints(auto_control)
check("auto mirrors its single setpoint on heat", auto_heat, 23.0)
check("auto mirrors its single setpoint on cool", auto_cool, 23.0)

local dry_heat, dry_cool = model.display_setpoints(drying)
check("dry keeps the stored heat setpoint", dry_heat, 22.0)
check("dry keeps the stored cool setpoint", dry_cool, 25.0)

local sparse_heat = model.display_setpoints(
  codec.parse("ret=OK,pow=1,mode=4,stemp=20.5,shum=0"))
check("heat setpoint falls back to stemp", sparse_heat, 20.5)

--------------------------------------------------------------------------
-- Mapping tables round trip
--------------------------------------------------------------------------

for st_mode, daikin_mode in pairs(C.ST_TO_DAIKIN_MODE) do
  check("mode round trip " .. st_mode, C.DAIKIN_TO_ST_MODE[daikin_mode], st_mode)
end
for st_fan, rate in pairs(C.ST_TO_FAN) do
  check("fan round trip " .. st_fan, C.FAN_TO_ST[rate], st_fan)
end
for st_swing, direction in pairs(C.ST_TO_SWING) do
  check("swing round trip " .. st_swing, C.SWING_TO_ST[direction], st_swing)
end

--------------------------------------------------------------------------

if failures > 0 then
  print(string.format("%d of %d checks failed", failures, checks))
  os.exit(1)
end
print(string.format("core tests passed (%d checks)", checks))
