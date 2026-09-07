-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- Minimal stand-ins for the SmartThings Edge runtime so that the driver
-- modules can be exercised off-hub. Only the surface the driver actually uses
-- is implemented.

local mocks = {}

--------------------------------------------------------------------------
-- log
--------------------------------------------------------------------------

mocks.log_lines = {}

local log = {}
for _, level in ipairs({ "trace", "debug", "info", "warn", "error" }) do
  log[level] = function(message)
    mocks.log_lines[#mocks.log_lines + 1] = level .. ": " .. tostring(message)
  end
end

--------------------------------------------------------------------------
-- ltn12
--------------------------------------------------------------------------

local ltn12 = {
  sink = {
    table = function(destination)
      return function(chunk)
        if chunk then destination[#destination + 1] = chunk end
        return 1
      end
    end,
  },
}

--------------------------------------------------------------------------
-- HTTP transport
--------------------------------------------------------------------------

-- Queued replies, keyed by request path. Each entry is a list of
-- { status = , body = } consumed in order; the last one repeats.
mocks.http_replies = {}
mocks.http_requests = {}

local function reply_for(url)
  local path = url:match("^http://[^/]+([^?]*)") or url
  local queue = mocks.http_replies[path]
  if not queue or #queue == 0 then return { status = 404, body = "" } end
  if #queue == 1 then return queue[1] end
  return table.remove(queue, 1)
end

local http = {}
function http.request(spec)
  mocks.http_requests[#mocks.http_requests + 1] = spec.url
  local reply = reply_for(spec.url)
  if reply.body then spec.sink(reply.body) end
  return 1, reply.status
end

--------------------------------------------------------------------------
-- Sockets
--------------------------------------------------------------------------

-- Queued UDP replies, each { body, source_address }.
mocks.udp_replies = {}
mocks.udp_sent = {}
mocks.udp_bind_failures = 0

local function make_udp()
  local index = 0
  local udp = {}
  function udp:setoption() return 1 end
  function udp:settimeout() return 1 end
  function udp:setsockname(_, port)
    if port ~= 0 and mocks.udp_bind_failures > 0 then
      mocks.udp_bind_failures = mocks.udp_bind_failures - 1
      return nil, "address already in use"
    end
    return 1
  end
  function udp:sendto(payload, address, port)
    mocks.udp_sent[#mocks.udp_sent + 1] = { payload = payload, address = address, port = port }
    return 1
  end
  function udp:receivefrom()
    index = index + 1
    local reply = mocks.udp_replies[index]
    if not reply then return nil, "timeout" end
    return reply[1], reply[2]
  end
  function udp:close() return 1 end
  return udp
end

local socket = {
  tcp = function() return { settimeout = function() return 1 end } end,
  udp = make_udp,
  sleep = function() end,
}

local cosock = {
  socket = socket,
  asyncify = function() return http end,
}

--------------------------------------------------------------------------
-- st.capabilities
--------------------------------------------------------------------------

local function attribute(capability_id, name)
  return setmetatable({ NAME = name }, {
    __call = function(_, value, extra)
      return { capability = capability_id, attribute = name, value = value, extra = extra }
    end,
    -- Supports the enum command style, e.g. switch.switch.on()
    __index = function(_, key)
      return function()
        return { capability = capability_id, attribute = name, value = key }
      end
    end,
  })
end

local capabilities = setmetatable({}, {
  __index = function(registry, capability_id)
    local entry = setmetatable({ ID = capability_id }, {
      __index = function(_, name) return attribute(capability_id, name) end,
    })
    rawset(registry, capability_id, entry)
    return entry
  end,
})

--------------------------------------------------------------------------
-- Devices and drivers
--------------------------------------------------------------------------

function mocks.make_device(network_id)
  local device = {
    device_network_id = network_id or "daikin-AABBCCDDEEFF",
    fields = {},
    events = {},
    preferences = {},
    status = "unknown",
    profile = { components = { main = { id = "main" }, outdoor = { id = "outdoor" } } },
  }

  device.timers = { active = {}, cancelled = {}, created = 0 }
  device.thread = {
    call_on_schedule = function(_, interval, callback, name)
      device.timers.created = device.timers.created + 1
      local timer = { kind = "schedule", interval = interval, callback = callback, name = name }
      device.timers.active[timer] = true
      return timer
    end,
    call_with_delay = function(_, delay, callback, name)
      device.timers.created = device.timers.created + 1
      local timer = { kind = "delay", interval = delay, callback = callback, name = name }
      device.timers.active[timer] = true
      return timer
    end,
    cancel_timer = function(_, timer)
      device.timers.active[timer] = nil
      device.timers.cancelled[#device.timers.cancelled + 1] = timer
      return timer
    end,
  }

  function device:get_field(key) return self.fields[key] end
  function device:set_field(key, value) self.fields[key] = value end
  function device:emit_event(event)
    event.component = "main"
    self.events[#self.events + 1] = event
  end
  function device:emit_component_event(component, event)
    event.component = component.id
    self.events[#self.events + 1] = event
  end
  function device:online() self.status = "online" end
  function device:offline() self.status = "offline" end

  return device
end

function mocks.make_driver(devices)
  local driver = {
    devices = devices or {},
    created = {},
    discovered_hosts = {},
    discovery_seen = {},
  }
  function driver:get_devices() return self.devices end
  function driver:try_create_device(spec) self.created[#self.created + 1] = spec end
  return driver
end

function mocks.active_timers(device)
  local count = 0
  for _ in pairs(device.timers.active) do count = count + 1 end
  return count
end

function mocks.reset()
  mocks.log_lines = {}
  mocks.http_replies = {}
  mocks.http_requests = {}
  mocks.udp_replies = {}
  mocks.udp_sent = {}
  mocks.udp_bind_failures = 0
end

--- Install the stand-ins so that require() inside the driver finds them.
function mocks.install()
  package.preload["log"] = function() return log end
  package.preload["ltn12"] = function() return ltn12 end
  package.preload["cosock"] = function() return cosock end
  package.preload["cosock.socket"] = function() return socket end
  package.preload["st.capabilities"] = function() return capabilities end
end

return mocks
