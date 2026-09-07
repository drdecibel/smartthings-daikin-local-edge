-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local C = {}

C.PROFILE = "daikin.local.brp069b4x.v1"
C.MANUFACTURER = "Daikin"
C.MODEL = "BRP069B4x"

-- Persisted/volatile device fields.
C.FIELD_HOST = "daikin_host"
C.FIELD_FAILURES = "daikin_failures"
C.FIELD_POLL_TIMER = "daikin_poll_timer"
C.FIELD_REFRESH_TIMER = "daikin_refresh_timer"
C.FIELD_LAST_RELOCATE = "daikin_last_relocate"
C.FIELD_LAST_ERROR = "daikin_last_error"

C.DEFAULT_POLL_INTERVAL = 300
C.MIN_POLL_INTERVAL = 60
C.MAX_POLL_INTERVAL = 3600
C.DEFAULT_SETPOINT = "22.0"

-- HTTP behaviour.
C.HTTP_PORT = 80
C.REQUEST_TIMEOUT = 4
C.REQUEST_ATTEMPTS = 2
C.RETRY_DELAY = 0.25

-- The device is only reported offline once several consecutive polls fail, so
-- a single dropped packet does not make the tile flap.
C.MAX_CONSECUTIVE_FAILURES = 3
-- Only look for a moved adapter this often (seconds).
C.RELOCATE_INTERVAL = 300

-- UDP discovery. The adapter answers a broadcast on 30050 from its own port,
-- so no hub address is ever needed.
C.DISCOVERY_PORT = 30050
C.DISCOVERY_SOURCE_PORT = 30000
C.DISCOVERY_MESSAGE = "DAIKIN_UDP/common/basic_info"
C.BROADCAST_ADDRESS = "255.255.255.255"
C.DISCOVERY_TIMEOUT = 4

-- SmartThings sends thermostat setpoints as a bare number with no unit. The
-- SmartThings reference drivers treat anything from 40 upwards as Fahrenheit.
C.FAHRENHEIT_THRESHOLD = 40
C.SETPOINT_STEP = 0.5

-- Documented Daikin per-mode setpoint limits for the legacy local API.
C.SETPOINT_RANGE = {
  heat = { min = 10.0, max = 31.0 },
  cool = { min = 18.0, max = 33.0 },
  auto = { min = 18.0, max = 31.0 },
}

-- get_sensor_info reports 999 (and 0) for a compressor that is not running.
C.COMPRESSOR_IDLE = 999

C.MODE = {
  AUTO = "0",
  AUTO_1 = "1",
  DRY = "2",
  COOL = "3",
  HEAT = "4",
  FAN = "6",
  AUTO_7 = "7",
}

-- Dry and fan-only do not take a numeric target temperature. The adapter
-- rejects the whole request with ret=PARAM NG if a number is sent instead.
C.MODE_SETPOINT_PLACEHOLDER = {
  [C.MODE.DRY] = "M",
  [C.MODE.FAN] = "--",
}

C.ST_TO_DAIKIN_MODE = {
  auto = C.MODE.AUTO,
  dryair = C.MODE.DRY,
  cool = C.MODE.COOL,
  heat = C.MODE.HEAT,
  fanonly = C.MODE.FAN,
}

C.DAIKIN_TO_ST_MODE = {
  ["0"] = "auto",
  ["1"] = "auto",
  ["2"] = "dryair",
  ["3"] = "cool",
  ["4"] = "heat",
  ["6"] = "fanonly",
  ["7"] = "auto",
}

C.SUPPORTED_THERMOSTAT_MODES = { "off", "auto", "heat", "cool", "dryair", "fanonly" }

-- Daikin fan rates: A=auto, B=silent, 3..7 = levels 1..5.
C.ST_TO_FAN = {
  auto = "A",
  low = "3",
  medium = "5",
  high = "6",
  turbo = "7",
}

C.FAN_TO_ST = {
  A = "auto",
  B = "low", -- Daikin quiet mode has no portable SmartThings equivalent.
  ["3"] = "low",
  ["4"] = "low",
  ["5"] = "medium",
  ["6"] = "high",
  ["7"] = "turbo",
}

C.SUPPORTED_FAN_MODES = { "auto", "low", "medium", "high", "turbo" }

C.ST_TO_SWING = {
  fixed = "0",
  vertical = "1",
  horizontal = "2",
  all = "3",
}

C.SWING_TO_ST = {
  ["0"] = "fixed",
  ["1"] = "vertical",
  ["2"] = "horizontal",
  ["3"] = "all",
}

C.SUPPORTED_SWING_MODES = { "fixed", "vertical", "horizontal", "all" }

return C
