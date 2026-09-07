-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 drdecibel
--
-- A very small HTTP GET client, written directly on a cosock TCP socket.
--
-- socket.http cannot be used here. The BRP069B4x web server matches the Host
-- header NAME case-sensitively and answers "HTTP/1.0 403 HTTP_FORBIDDEN" to
-- anything other than an exact "Host:" -- lowercase "host:", "HOST:" and
-- "hOsT:" are all rejected. That contradicts RFC 7230, which defines field
-- names as case-insensitive, but the adapter firmware is what it is.
-- LuaSocket lowercases every header name before sending, so socket.http can
-- never satisfy it. Building the request here keeps the bytes exact.
--
-- The adapter answers HTTP/1.0 with Content-Length and closes the connection,
-- and every response body is well under a kilobyte, so no chunked decoding or
-- connection reuse is needed.

local socket = require("cosock.socket")
local C = require("constants")
local codec = require("codec")

local http = {}

--- Split "host" or "host:port" into a name and a port number.
function http.split_host(host)
  host = tostring(host)
  local name, port = host:match("^(.-):(%d+)$")
  if name and name ~= "" then return name, tonumber(port) end
  return host, C.HTTP_PORT
end

--- Build the exact request bytes. Kept separate so the wire format, and in
--- particular the capitalisation of Host, is covered by the unit tests.
function http.build_request(host, path, params)
  local target = path
  local query = codec.query(params)
  if query ~= "" then target = target .. "?" .. query end
  return table.concat({
    "GET " .. target .. " HTTP/1.1",
    "Host: " .. host,
    "Connection: close",
    "",
    "",
  }, "\r\n")
end

function http.parse_status(line)
  if type(line) ~= "string" then return nil end
  return tonumber(line:match("^HTTP/%d%.%d%s+(%d%d%d)"))
end

-- Reads up to the blank line. Returns the Content-Length when the adapter
-- sent one, or nil plus a reason if the connection died mid-header.
local function read_headers(sock)
  local length
  while true do
    local line, err = sock:receive("*l")
    if not line then return nil, err or "closed" end
    if line == "" then return length end
    local name, value = line:match("^([^:]+):%s*(.-)%s*$")
    if name and name:lower() == "content-length" then
      length = tonumber(value)
    end
  end
end

local function read_body(sock, length)
  local body, err, partial
  if length and length > 0 then
    body, err, partial = sock:receive(length)
  else
    body, err, partial = sock:receive("*a")
  end
  body = body or partial
  if body == nil then return nil, err or "closed" end
  return body
end

--- Perform the request. Returns the status code and body, or nil and a reason.
function http.get(host, path, params)
  local name, port = http.split_host(host)

  local sock, err = socket.tcp()
  if not sock then return nil, "socket: " .. codec.redact(err) end
  sock:settimeout(C.REQUEST_TIMEOUT)

  local ok
  ok, err = sock:connect(name, port)
  if not ok then
    sock:close()
    return nil, "connect: " .. codec.redact(err)
  end

  ok, err = sock:send(http.build_request(host, path, params))
  if not ok then
    sock:close()
    return nil, "send: " .. codec.redact(err)
  end

  local status_line
  status_line, err = sock:receive("*l")
  local status = http.parse_status(status_line)
  if not status then
    sock:close()
    return nil, "no status line: " .. codec.redact(err or status_line)
  end

  local length, header_error = read_headers(sock)
  if length == nil and header_error then
    sock:close()
    return nil, "headers: " .. codec.redact(header_error)
  end

  local body, body_error = read_body(sock, length)
  sock:close()
  if body == nil then return nil, "body: " .. codec.redact(body_error) end
  return status, body
end

return http
