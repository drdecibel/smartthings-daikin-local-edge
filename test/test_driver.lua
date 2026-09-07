-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Exercises the request, command, discovery and lifecycle paths against
-- stand-ins for the SmartThings Edge runtime. No hub and no adapter needed.

package.path = "./src/?.lua;./test/?.lua;" .. package.path

local mocks = require("support.mocks")
mocks.install()

local C = require("constants")
local http = require("http")
local api = require("api")
local commands = require("commands")
local discovery = require("discovery")
local lifecycle = require("lifecycle")

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

local function check_truthy(label, value)
  checks = checks + 1
  if not value then
    failures = failures + 1
    print("FAIL " .. label .. "\n  expected a truthy value")
  end
end

local HOST = "192.0.2.10"

local CONTROL_BODY = "ret=OK,pow=0,mode=3,adv=,stemp=25.0,shum=0," ..
  "dt1=25.0,dt2=M,dt3=25.0,dt4=22.0,dt7=25.0," ..
  "dh1=AUTO,dh2=50,dh3=0,dh4=0,dh7=AUTO," ..
  "alert=255,f_rate=7,f_dir=1," ..
  "dfr1=5,dfr2=5,dfr3=7,dfr4=5,dfr6=5,dfr7=5," ..
  "dfd1=0,dfd2=0,dfd3=1,dfd4=0,dfd6=0,dfd7=0"
local SENSOR_BODY = "ret=OK,htemp=24.0,hhum=-,otemp=15.0,err=0,cmpfreq=999"

local function ok(body) return { status = 200, body = body } end

local function serve_normal()
  mocks.http_replies["/aircon/get_control_info"] = { ok(CONTROL_BODY) }
  mocks.http_replies["/aircon/get_sensor_info"] = { ok(SENSOR_BODY) }
  mocks.http_replies["/aircon/set_control_info"] = { ok("ret=OK") }
end

local function ready_device()
  local device = mocks.make_device()
  device:set_field(C.FIELD_HOST, HOST)
  return device
end

local function last_request()
  return mocks.http_requests[#mocks.http_requests]
end

local function find_event(device, attribute)
  for index = #device.events, 1, -1 do
    if device.events[index].attribute == attribute then return device.events[index] end
  end
  return nil
end

--------------------------------------------------------------------------
-- HTTP wire format
--
-- The BRP069B4x matches the Host header name case-sensitively and answers
-- 403 to anything but an exact "Host:". These checks pin the bytes down.
--------------------------------------------------------------------------

check("request line and headers",
  http.build_request(HOST, "/aircon/get_control_info"),
  "GET /aircon/get_control_info HTTP/1.1\r\nHost: 192.0.2.10\r\nConnection: close\r\n\r\n")

local request_bytes = http.build_request(HOST, "/aircon/get_control_info")
check_truthy("Host is capitalised", request_bytes:find("\r\nHost: ", 1, true))
check("no lowercase host header", request_bytes:find("\r\nhost: ", 1, true), nil)
check("no uppercase host header", request_bytes:find("\r\nHOST: ", 1, true), nil)
-- LuaSocket adds these and lowercases every name, which is why socket.http
-- cannot be used against this adapter.
check("no user-agent header", request_bytes:lower():find("user%-agent"), nil)
check("no te header", request_bytes:lower():find("\r\nte:"), nil)

check("query string is appended in order",
  http.build_request(HOST, "/aircon/set_control_info", {
    { name = "pow", value = "1" },
    { name = "stemp", value = "M" },
  }),
  "GET /aircon/set_control_info?pow=1&stemp=M HTTP/1.1\r\nHost: 192.0.2.10\r\nConnection: close\r\n\r\n")

check("host carries the port when one is configured",
  (http.build_request("192.0.2.10:8080", "/x")):match("Host: ([^\r]+)"), "192.0.2.10:8080")

local name, port = http.split_host(HOST)
check("default port", port, 80)
check("default host name", name, HOST)
name, port = http.split_host("heatpump.lan:8080")
check("explicit port", port, 8080)
check("explicit host name", name, "heatpump.lan")

check("status parsed from HTTP/1.0", http.parse_status("HTTP/1.0 200 OK"), 200)
check("forbidden status parsed", http.parse_status("HTTP/1.1 403 HTTP_FORBIDDEN"), 403)
check("garbage status", http.parse_status("not a status line"), nil)
check("missing status", http.parse_status(nil), nil)

--------------------------------------------------------------------------
-- api: URL building, ret validation, retries
--------------------------------------------------------------------------

mocks.reset()
serve_normal()
local control = api.control_info(HOST)
check("control info parsed", control.mode, "3")
check("control info url", last_request(), "http://192.0.2.10/aircon/get_control_info")

api.set_control_info(HOST, {
  { name = "pow", value = "1" },
  { name = "mode", value = "2" },
  { name = "stemp", value = "M" },
})
check("set url keeps the documented parameter order",
  last_request(), "http://192.0.2.10/aircon/set_control_info?pow=1&mode=2&stemp=M")

mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = { { status = 200, body = "ret=PARAM NG" } }
local refused, refusal = api.control_info(HOST)
check("refused request returns no data", refused, nil)
check("refusal is reported as an adapter answer", refusal, "adapter: PARAM NG")
check("a refusal is not retried", #mocks.http_requests, 1)

mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = {
  { status = 500, body = "" },
  ok(CONTROL_BODY),
}
local retried = api.control_info(HOST)
check("transport failure is retried", retried and retried.mode, "3")
check("retry count", #mocks.http_requests, 2)

mocks.reset()
local missing, missing_reason = api.control_info(nil)
check("missing host is refused", missing, nil)
check("missing host reason", missing_reason, "no adapter address configured")
check("no request was attempted", #mocks.http_requests, 0)

-- A 403 is what the adapter returns when the request is malformed for it.
mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = {
  { status = 403, reason = "HTTP_FORBIDDEN", body = "" },
}
local forbidden, forbidden_reason = api.control_info(HOST)
check("403 is reported", forbidden, nil)
check("403 reason", forbidden_reason, "http 403")
check("403 is retried", #mocks.http_requests, C.REQUEST_ATTEMPTS)

mocks.reset()
mocks.connect_failure = "connection refused"
local unreachable, unreachable_reason = api.control_info(HOST)
check("unreachable adapter is reported", unreachable, nil)
check("connect failure reason", unreachable_reason, "transport: connect: connection refused")
check("connect failure is retried", #mocks.tcp_connections, C.REQUEST_ATTEMPTS)

-- Responses without Content-Length are read until the adapter closes.
mocks.reset()
mocks.http_replies["/aircon/get_sensor_info"] = {
  { raw = "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\n" .. SENSOR_BODY },
}
local streamed = api.sensor_info(HOST)
check("body read to end of stream", streamed and streamed.htemp, "24.0")

-- Local addresses must never reach the log.
mocks.reset()
mocks.connect_failure = "no route to 198.51.100.7"
api.control_info(HOST)
check("addresses are redacted in the log",
  table.concat(mocks.log_lines, "\n"):find("198.51.100.7", 1, true), nil)
check_truthy("redaction placeholder is used",
  table.concat(mocks.log_lines, "\n"):find("<address>", 1, true))

--------------------------------------------------------------------------
-- refresh: events, online state, failure debounce
--------------------------------------------------------------------------

mocks.reset()
serve_normal()
local driver = mocks.make_driver()
local device = ready_device()
driver.devices = { device }

check_truthy("refresh succeeds", commands.refresh(driver, device))
check("device is online", device.status, "online")
check("power reported off", find_event(device, "switch").value, "off")
check("thermostat mode reported off", find_event(device, "thermostatMode").value, "off")
check("operating state idle", find_event(device, "thermostatOperatingState").value, "idle")
check("fan mode mapped to turbo", find_event(device, "fanMode").value, "turbo")
check("swing mapped to vertical", find_event(device, "fanOscillationMode").value, "vertical")
check("heating setpoint", find_event(device, "heatingSetpoint").value.value, 22.0)
check("cooling setpoint", find_event(device, "coolingSetpoint").value.value, 25.0)

local indoor, outdoor
for _, event in ipairs(device.events) do
  if event.attribute == "temperature" and event.component == "main" then indoor = event end
  if event.attribute == "temperature" and event.component == "outdoor" then outdoor = event end
end
check("indoor temperature", indoor and indoor.value.value, 24.0)
check("indoor unit", indoor and indoor.value.unit, "C")
check("outdoor temperature", outdoor and outdoor.value.value, 15.0)

-- A missing humidity sensor reports "-", which must not become an event.
mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = { ok(CONTROL_BODY) }
mocks.http_replies["/aircon/get_sensor_info"] = { ok("ret=OK,htemp=-,otemp=--,err=0,cmpfreq=0") }
local sparse = ready_device()
commands.refresh(driver, sparse)
check("sentinel temperatures are skipped", find_event(sparse, "temperature"), nil)
check("device still online", sparse.status, "online")

-- Transport failures must not take the device offline immediately.
mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = { { status = 500, body = "" } }
local flaky = ready_device()
commands.refresh(driver, flaky)
check("one failure keeps the device available", flaky.status, "unknown")
check("failure counter", flaky:get_field(C.FIELD_FAILURES), 1)
commands.refresh(driver, flaky)
check("two failures still keep the device available", flaky.status, "unknown")
commands.refresh(driver, flaky)
check("third failure marks the device offline", flaky.status, "offline")
check("failure counter reached the threshold",
  flaky:get_field(C.FIELD_FAILURES), C.MAX_CONSECUTIVE_FAILURES)

mocks.http_replies["/aircon/get_control_info"] = { ok(CONTROL_BODY) }
mocks.http_replies["/aircon/get_sensor_info"] = { ok(SENSOR_BODY) }
commands.refresh(driver, flaky)
check("recovery brings the device back online", flaky.status, "online")
check("failure counter is cleared", flaky:get_field(C.FIELD_FAILURES), 0)

--------------------------------------------------------------------------
-- commands
--------------------------------------------------------------------------

local function run_command(fn, ...)
  mocks.reset()
  serve_normal()
  local target = ready_device()
  fn(driver, target, ...)
  return target
end

local powered = run_command(commands.on)
check("power on sends the complete control state",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=1&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=1")
check("a state read is scheduled after the command", mocks.active_timers(powered), 1)

run_command(commands.off)
check("power off keeps the current mode",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=1")

run_command(commands.set_mode, { args = { mode = "heat" } })
check("heat mode restores the stored heat settings",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=1&mode=4&stemp=22.0&shum=0&f_rate=5&f_dir=0")

run_command(commands.set_mode, { args = { mode = "dryair" } })
check("dry mode sends the placeholder temperature",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=1&mode=2&stemp=M&shum=50&f_rate=5&f_dir=0")

run_command(commands.set_mode, { args = { mode = "fanonly" } })
check("fan only sends the placeholder temperature",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=1&mode=6&stemp=--&shum=0&f_rate=5&f_dir=0")

local unsupported = run_command(commands.set_mode, { args = { mode = "eco" } })
check("an unsupported mode is never sent", #mocks.http_requests, 1)
check("an unsupported mode schedules nothing", mocks.active_timers(unsupported), 0)

run_command(commands.set_heat, { args = { setpoint = 21 } })
check("heating setpoint selects heat mode without powering on",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=4&stemp=21.0&shum=0&f_rate=5&f_dir=0")

run_command(commands.set_heat, { args = { setpoint = 72 } })
check("a fahrenheit setpoint is converted",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=4&stemp=22.0&shum=0&f_rate=5&f_dir=0")

run_command(commands.set_cool, { args = { setpoint = 24.3 } })
check("cooling setpoint is rounded to a half degree",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=3&stemp=24.5&shum=0&f_rate=7&f_dir=1")

run_command(commands.set_fan, { args = { fanMode = "medium" } })
check("fan rate change preserves the rest of the state",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=3&stemp=25.0&shum=0&f_rate=5&f_dir=1")

run_command(commands.set_swing, { args = { fanOscillationMode = "all" } })
check("swing change preserves the rest of the state",
  last_request(),
  "http://192.0.2.10/aircon/set_control_info?pow=0&mode=3&stemp=25.0&shum=0&f_rate=7&f_dir=3")

local bad_fan = run_command(commands.set_fan, { args = { fanMode = "hurricane" } })
check("an unsupported fan mode is never sent", #mocks.http_requests, 0)
check("an unsupported fan mode schedules nothing", mocks.active_timers(bad_fan), 0)

-- A refused command means the adapter is reachable, so it stays online.
mocks.reset()
mocks.http_replies["/aircon/get_control_info"] = { ok(CONTROL_BODY) }
mocks.http_replies["/aircon/set_control_info"] = { { status = 200, body = "ret=PARAM NG" } }
local refused_device = ready_device()
commands.on(driver, refused_device)
check("a refused command keeps the device online", refused_device.status, "online")
check("a refused command clears the failure counter",
  refused_device:get_field(C.FIELD_FAILURES), 0)

--------------------------------------------------------------------------
-- Address preference handling
--------------------------------------------------------------------------

mocks.reset()
serve_normal()
local pinned = mocks.make_device()
pinned:set_field(C.FIELD_HOST, "198.51.100.7")
pinned.preferences.hostOverride = "192.0.2.10"
commands.refresh(driver, pinned)
check("the configured address wins",
  mocks.http_requests[1], "http://192.0.2.10/aircon/get_control_info")

mocks.reset()
serve_normal()
local invalid = mocks.make_device()
invalid:set_field(C.FIELD_HOST, HOST)
invalid.preferences.hostOverride = "not a host!"
commands.refresh(driver, invalid)
check("an unusable address falls back to the discovered one",
  mocks.http_requests[1], "http://192.0.2.10/aircon/get_control_info")

--------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------

local BASIC_INFO = "ret=OK,type=aircon,ver=4_2_303,name=%44%61%69%6b%69%6e," ..
  "adp_kind=3,mac=AABBCCDDEEFF"

local function discover_once(target_driver)
  local rounds = 0
  discovery.handle(target_driver, nil, function()
    rounds = rounds + 1
    return rounds == 1
  end)
end

mocks.reset()
mocks.udp_replies = { { BASIC_INFO, HOST } }
local disco_driver = mocks.make_driver()
discover_once(disco_driver)
check("one device is created", #disco_driver.created, 1)
check("device network id", disco_driver.created[1].device_network_id, "daikin-AABBCCDDEEFF")
check("device label comes from the adapter", disco_driver.created[1].label, "Daikin")
check("profile", disco_driver.created[1].profile, C.PROFILE)
check("address remembered", disco_driver.discovered_hosts["daikin-AABBCCDDEEFF"], HOST)
check("broadcast target", mocks.udp_sent[1].address, "255.255.255.255")
check("broadcast port", mocks.udp_sent[1].port, 30050)
check("broadcast payload", mocks.udp_sent[1].payload, "DAIKIN_UDP/common/basic_info")
check("no adapter identifier is logged",
  table.concat(mocks.log_lines, "\n"):find("AABBCCDDEEFF", 1, true), nil)

-- The same adapter answering twice in one session must not be created twice.
mocks.reset()
mocks.udp_replies = { { BASIC_INFO, HOST }, { BASIC_INFO, HOST } }
disco_driver = mocks.make_driver()
discover_once(disco_driver)
check("duplicate answers create one device", #disco_driver.created, 1)

-- An adapter that already has a device must not be created again.
mocks.reset()
mocks.udp_replies = { { BASIC_INFO, HOST } }
disco_driver = mocks.make_driver({ mocks.make_device("daikin-AABBCCDDEEFF") })
discover_once(disco_driver)
check("an existing device is not duplicated", #disco_driver.created, 0)
check("its address is still refreshed",
  disco_driver.discovered_hosts["daikin-AABBCCDDEEFF"], HOST)

-- After the device is deleted, a new scan must be able to add it again.
mocks.reset()
mocks.udp_replies = { { BASIC_INFO, HOST } }
disco_driver = mocks.make_driver()
discover_once(disco_driver)
mocks.reset()
mocks.udp_replies = { { BASIC_INFO, HOST } }
discover_once(disco_driver)
check("a later scan can add the device again", #disco_driver.created, 2)

-- Non Daikin answers on the wire are ignored.
mocks.reset()
mocks.udp_replies = {
  { "ret=OK,type=coffee,mac=AABBCCDDEEFF", HOST },
  { "garbage", HOST },
  { "ret=NG,type=aircon,mac=AABBCCDDEEFF", HOST },
}
disco_driver = mocks.make_driver()
discover_once(disco_driver)
check("unrelated answers are ignored", #disco_driver.created, 0)

-- A busy source port must not stop discovery.
mocks.reset()
mocks.udp_bind_failures = 1
mocks.udp_replies = { { BASIC_INFO, HOST } }
disco_driver = mocks.make_driver()
discover_once(disco_driver)
check("discovery falls back to an ephemeral port", #disco_driver.created, 1)

-- An adapter that changed address is found again and the device is updated.
mocks.reset()
mocks.udp_replies = { { BASIC_INFO, "192.0.2.55" } }
local moved_driver = mocks.make_driver()
local moved = mocks.make_device("daikin-AABBCCDDEEFF")
moved:set_field(C.FIELD_HOST, HOST)
check("relocate returns the new address",
  discovery.relocate(moved_driver, moved), "192.0.2.55")
check("the new address is stored", moved:get_field(C.FIELD_HOST), "192.0.2.55")

mocks.reset()
mocks.udp_replies = { { "ret=OK,type=aircon,mac=FFEEDDCCBBAA", "192.0.2.60" } }
local other = mocks.make_device("daikin-AABBCCDDEEFF")
other:set_field(C.FIELD_HOST, HOST)
check("another adapter is not adopted", discovery.relocate(moved_driver, other), nil)
check("the stored address is unchanged", other:get_field(C.FIELD_HOST), HOST)

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

mocks.reset()
serve_normal()
local life_driver = mocks.make_driver()
life_driver.discovered_hosts["daikin-AABBCCDDEEFF"] = HOST
local added = mocks.make_device()
life_driver.devices = { added }
lifecycle.added(life_driver, added)
check("the discovered address is persisted", added:get_field(C.FIELD_HOST), HOST)
check("exactly one polling timer", mocks.active_timers(added), 1)
check("supported modes published", find_event(added, "supportedThermostatModes").value[1], "off")
check("supported fan modes published", find_event(added, "supportedAcFanModes").value[5], "turbo")
check("setpoint range published",
  find_event(added, "heatingSetpointRange").value.value.maximum, 31.0)
check("device polled on startup", added.status, "online")

local poll_timer
for timer in pairs(added.timers.active) do poll_timer = timer end
check("polling uses the configured default interval",
  poll_timer.interval, C.DEFAULT_POLL_INTERVAL)

added.preferences.pollInterval = "60"
lifecycle.info_changed(life_driver, added)
check("changing the preference leaves one timer", mocks.active_timers(added), 1)
check("the old timer was cancelled", #added.timers.cancelled >= 1, true)
for timer in pairs(added.timers.active) do poll_timer = timer end
check("the new interval is applied", poll_timer.interval, 60)

lifecycle.init(life_driver, added)
check("re-initialising does not stack timers", mocks.active_timers(added), 1)

lifecycle.removed(life_driver, added)
check("removal cancels every timer", mocks.active_timers(added), 0)
check("removal forgets the address",
  life_driver.discovered_hosts["daikin-AABBCCDDEEFF"], nil)
check("removal clears the discovery marker",
  life_driver.discovery_seen["daikin-AABBCCDDEEFF"], nil)

--------------------------------------------------------------------------

if failures > 0 then
  print(string.format("%d of %d checks failed", failures, checks))
  os.exit(1)
end
print(string.format("driver tests passed (%d checks)", checks))
