-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

package.path = "./src/?.lua;" .. package.path

local codec = require("codec")
local model = require("model")

local basic = codec.parse("ret=OK,type=aircon,name=%44%61%69%6b%69%6e,adp_kind=3")
assert(basic.ret == "OK")
assert(basic.name == "Daikin")
assert(codec.decode("Living+room") == "Living room")

local control = codec.parse("ret=OK,pow=0,mode=4,stemp=22.0,shum=0,dt3=23.0,dt4=22.0,f_rate=A,dfr3=5,dfr4=A,f_dir=0,dfd3=1,dfd4=0")
local payload = model.make_payload(control, { pow = "1" })
assert(payload.pow == "1")
assert(payload.mode == "4")
assert(payload.stemp == "22.0")
assert(payload.f_rate == "A")
assert(payload.f_dir == "0")

local cool = model.make_payload(control, { mode = "3" })
assert(cool.mode == "3")
assert(cool.stemp == "23.0")
assert(cool.f_rate == "5")
assert(cool.f_dir == "1")

assert(model.thermostat_mode(control) == "off")
control.pow = "1"
assert(model.thermostat_mode(control) == "heat")
assert(model.operating_state(control, { cmpfreq = "0", mompow = "1" }) == "idle")
assert(model.operating_state(control, { cmpfreq = "18", mompow = "1" }) == "heating")
assert(model.clean_host(" http://192.0.2.10/aircon/get_sensor_info ") == "192.0.2.10")

print("core tests passed")
