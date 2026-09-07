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
-- TCP transport
--------------------------------------------------------------------------

-- Queued replies keyed by request path. Each entry is a list of
-- { status = , body = } (or { raw = }) consumed in order; a single entry
-- repeats. Set mocks.connect_failure to make connect() fail.
mocks.http_replies = {}
mocks.http_requests = {}   -- reconstructed URLs, for readable assertions
mocks.tcp_requests = {}    -- the exact bytes the driver sent
mocks.tcp_connections = {}
mocks.connect_failure = nil

local function build_raw(reply)
  if reply.raw then return reply.raw end
  local body = reply.body or ""
  return table.concat({
    "HTTP/1.0 " .. tostring(reply.status) .. " " .. (reply.reason or "OK"),
    "Content-Length: " .. tostring(#body),
    "Content-Type: text/plain",
    "",
    body,
  }, "\r\n")
end

local function reply_for(path)
  local queue = mocks.http_replies[path]
  if not queue or #queue == 0 then return { status = 404, body = "" } end
  if #queue == 1 then return queue[1] end
  return table.remove(queue, 1)
end

local function make_tcp()
  local sock = { buffer = "", position = 1, authority = nil }

  function sock:settimeout() return 1 end

  function sock:connect(name, port)
    self.authority = tostring(name) .. ":" .. tostring(port)
    mocks.tcp_connections[#mocks.tcp_connections + 1] = { name = name, port = port }
    if mocks.connect_failure then return nil, mocks.connect_failure end
    return 1
  end

  function sock:send(data)
    mocks.tcp_requests[#mocks.tcp_requests + 1] = data
    local target = data:match("^GET%s+(%S+)") or ""
    local path = target:match("^([^?]*)") or target
    local authority = self.authority or ""
    -- Drop the default port so assertions read like ordinary URLs.
    authority = authority:gsub(":80$", "")
    mocks.http_requests[#mocks.http_requests + 1] = "http://" .. authority .. target
    self.buffer = build_raw(reply_for(path))
    self.position = 1
    return #data
  end

  function sock:receive(pattern)
    if pattern == "*l" or pattern == "l" then
      if self.position > #self.buffer then return nil, "closed" end
      local first, last = self.buffer:find("\r\n", self.position, true)
      if not first then
        local rest = self.buffer:sub(self.position)
        self.position = #self.buffer + 1
        return rest
      end
      local line = self.buffer:sub(self.position, first - 1)
      self.position = last + 1
      return line
    end

    if pattern == "*a" or pattern == "a" then
      local rest = self.buffer:sub(self.position)
      self.position = #self.buffer + 1
      return rest
    end

    if type(pattern) == "number" then
      local chunk = self.buffer:sub(self.position, self.position + pattern - 1)
      self.position = self.position + #chunk
      if #chunk < pattern then return nil, "closed", chunk end
      return chunk
    end

    return nil, "unsupported pattern"
  end

  function sock:close() return 1 end

  return sock
end

--------------------------------------------------------------------------
-- UDP
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
  tcp = make_tcp,
  udp = make_udp,
  sleep = function() end,
}

local cosock = {
  socket = socket,
  asyncify = function() return {} end,
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
  mocks.tcp_requests = {}
  mocks.tcp_connections = {}
  mocks.connect_failure = nil
  mocks.udp_replies = {}
  mocks.udp_sent = {}
  mocks.udp_bind_failures = 0
end

--- Install the stand-ins so that require() inside the driver finds them.
function mocks.install()
  package.preload["log"] = function() return log end
  package.preload["cosock"] = function() return cosock end
  package.preload["cosock.socket"] = function() return socket end
  package.preload["st.capabilities"] = function() return capabilities end
end

return mocks
