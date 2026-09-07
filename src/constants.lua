-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel

local C = {}

C.PROFILE = "daikin.local.brp069b4x.v1"
C.MANUFACTURER = "Daikin"
C.MODEL = "BRP069B4x"
C.FIELD_HOST = "daikin_host"
C.DEFAULT_POLL_INTERVAL = 300
C.DEFAULT_SETPOINT = "22.0"

C.MODE = {
  AUTO = "0",
  DRY = "2",
  COOL = "3",
  HEAT = "4",
  FAN = "6",
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

C.ST_TO_FAN = {
  auto = "A",
  low = "3",
  medium = "5",
  high = "7",
}

C.FAN_TO_ST = {
  A = "auto",
  B = "low", -- Daikin quiet mode has no portable SmartThings equivalent.
  ["3"] = "low",
  ["4"] = "low",
  ["5"] = "medium",
  ["6"] = "high",
  ["7"] = "high",
}

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

return C
