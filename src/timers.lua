-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Timer handles are kept in device fields and cancelled explicitly, so the
-- driver only ever cancels its own timers and does not depend on the internal
-- timer table of the device thread.

local timers = {}

function timers.cancel(device, field)
  local timer = device:get_field(field)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(field, nil)
  end
end

function timers.set_interval(device, field, seconds, callback, name)
  timers.cancel(device, field)
  device:set_field(field, device.thread:call_on_schedule(seconds, callback, name))
end

function timers.set_timeout(device, field, seconds, callback, name)
  timers.cancel(device, field)
  device:set_field(field, device.thread:call_with_delay(seconds, callback, name))
end

return timers
