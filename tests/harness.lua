local root = ROOT or "out"
local cache, dirs = {}, { root .. "/Server" }
local function normalize(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then table.remove(parts) elseif part ~= "." then parts[#parts + 1] = part end
  end
  return (path:sub(1, 1) == "/" and "/" or "") .. table.concat(parts, "/")
end
Package = {
  Require = function(path)
    local base = path:sub(1, 1) == "." and dirs[#dirs] or root
    local full = normalize(base .. "/" .. path)
    if cache[full] == nil then
      dirs[#dirs + 1] = full:match("(.*)/")
      cache[full] = dofile(full)
      table.remove(dirs)
    end
    return cache[full]
  end,
  Export = function(name, value) _G[name] = value end
}
local clock = 1782900000000
Server = { GetTime = function() clock = clock + 1 return clock end }
DatabaseEngine = { SQLite = 0, MySQL = 1, PostgreSQL = 2 }
Vector = function(x, y, z) return { X = x, Y = y, Z = z } end
Rotator = function(p, y, r) return { Pitch = p, Yaw = y, Roll = r } end
Color = function(r, g, b, a) return { R = r, G = g, B = b, A = a } end
function req(name) return Package.Require(name .. ".lua") end
function check(name, got, want)
  local ok = got == want
  print((ok and "OK  " or "FAIL") .. " " .. name .. " => " .. tostring(got) .. (ok and "" or ("   expected " .. tostring(want))))
end

local function decodeJson(text)
  local position = 1
  local function skip() position = text:find("%S", position) or #text + 1 end
  local value
  local function parseString()
    local result = {}
    position = position + 1
    while true do
      local char = text:sub(position, position)
      if char == '"' then position = position + 1 break end
      if char == "\\" then
        local nextChar = text:sub(position + 1, position + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
        result[#result + 1] = map[nextChar] or nextChar
        position = position + 2
      else
        result[#result + 1] = char
        position = position + 1
      end
    end
    return table.concat(result)
  end
  function value()
    skip()
    local char = text:sub(position, position)
    if char == "[" then
      position = position + 1
      local array = {}
      skip()
      if text:sub(position, position) == "]" then position = position + 1 return array end
      while true do
        array[#array + 1] = value()
        skip()
        local separator = text:sub(position, position)
        position = position + 1
        if separator == "]" then return array end
      end
    elseif char == "{" then
      position = position + 1
      local object = {}
      skip()
      if text:sub(position, position) == "}" then position = position + 1 return object end
      while true do
        skip()
        local key = parseString()
        skip()
        position = position + 1
        object[key] = value()
        skip()
        local separator = text:sub(position, position)
        position = position + 1
        if separator == "}" then return object end
      end
    elseif char == '"' then
      return parseString()
    elseif text:sub(position, position + 3) == "null" then
      position = position + 4
      return nil
    elseif text:sub(position, position + 3) == "true" then
      position = position + 4
      return true
    elseif text:sub(position, position + 4) == "false" then
      position = position + 5
      return false
    end
    local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
    position = position + #number
    return math.tointeger(tonumber(number)) or tonumber(number)
  end
  local results = {}
  skip()
  while position <= #text do
    results[#results + 1] = value()
    skip()
  end
  return results
end

local function sqlLiteral(v)
  if type(v) == "number" then
    if math.type(v) == "integer" then return tostring(v) end
    return string.format("%.17g", v)
  elseif type(v) == "boolean" then
    return v and "1" or "0"
  end
  return "'" .. tostring(v):gsub("'", "''") .. "'"
end

local function encodeJson(value)
  local valueType = type(value)
  if valueType == "table" then
    if #value > 0 or next(value) == nil then
      local items = {}
      for _, item in ipairs(value) do items[#items + 1] = encodeJson(item) end
      return "[" .. table.concat(items, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    local entries = {}
    for _, key in ipairs(keys) do entries[#entries + 1] = string.format("%q", key) .. ":" .. encodeJson(value[key]) end
    return "{" .. table.concat(entries, ",") .. "}"
  elseif valueType == "string" then
    return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
  elseif valueType == "number" then
    return math.type(value) == "integer" and tostring(value) or string.format("%.17g", value)
  elseif valueType == "boolean" then
    return tostring(value)
  end
  return "null"
end
JSON = {
  stringify = function(value) return encodeJson(value) end,
  parse = function(text) return decodeJson(text)[1] end
}

SqlLog = {}
local Db = {}
Db.__index = Db
function Database(engine, file, pool)
  return setmetatable({ file = file }, Db)
end
local function render(sql, params)
  return (sql:gsub(":(%d+)", function(index) return sqlLiteral(params[tonumber(index) + 1]) end))
end
function Db:exec(lines)
  local script = os.tmpname()
  local handle = io.open(script, "w")
  handle:write(table.concat(lines, "\n") .. "\n")
  handle:close()
  local process = io.popen("sqlite3 " .. self.file .. " < " .. script .. " 2>&1")
  local output = process:read("a")
  process:close()
  os.remove(script)
  if output:find("Error") or output:find("error") then
    return nil, output:gsub("%s+$", "")
  end
  return decodeJson(output), nil
end
function Db:run(sql, params, wantChanges)
  SqlLog[#SqlLog + 1] = sql
  if sql == "BEGIN" or sql == "START TRANSACTION" then
    self.tx = {}
    return {}, nil
  elseif sql == "COMMIT" then
    local lines = { ".bail on", "PRAGMA foreign_keys = ON;", "BEGIN;" }
    for _, statement in ipairs(self.tx or {}) do lines[#lines + 1] = statement .. ";" end
    lines[#lines + 1] = "COMMIT;"
    self.tx = nil
    local _, err = self:exec(lines)
    return {}, err
  elseif sql == "ROLLBACK" then
    self.tx = nil
    return {}, nil
  end
  local rendered = render(sql, params)
  local lines = { ".bail on", "PRAGMA foreign_keys = ON;" }
  if self.tx then
    lines[#lines + 1] = ".output /dev/null"
    lines[#lines + 1] = "BEGIN;"
    for _, statement in ipairs(self.tx) do lines[#lines + 1] = statement .. ";" end
    lines[#lines + 1] = ".output"
  end
  lines[#lines + 1] = ".mode json"
  lines[#lines + 1] = rendered .. ";"
  if wantChanges then lines[#lines + 1] = "SELECT changes() AS __changes;" end
  if self.tx then lines[#lines + 1] = "ROLLBACK;" end
  local result, err = self:exec(lines)
  if result ~= nil and self.tx and not rendered:match("^SELECT") then
    self.tx[#self.tx + 1] = rendered
  end
  return result, err
end
function Db:SelectAsync(sql, callback, ...)
  local results, err = self:run(sql, { ... }, false)
  if results == nil then callback(nil, err) return end
  callback(results[1] or {}, "")
end
function Db:ExecuteAsync(sql, callback, ...)
  local results, err = self:run(sql, { ... }, true)
  if results == nil then callback(nil, err) return end
  local last = results[#results]
  callback(last and last[1] and last[1].__changes or 0, "")
end
function Db:Close() end
local FileMeta = {}
FileMeta.__index = FileMeta
File = setmetatable({}, { __call = function(_, path, truncate)
  return setmetatable({ handle = io.open(path, truncate and "w" or "a+") }, FileMeta)
end })
function FileMeta:Write(data) self.handle:write(data) end
function FileMeta:Close() self.handle:close() end
function File.CreateDirectory(path) os.execute("mkdir -p '" .. path .. "'") return true end
function File.Exists(path) local f = io.open(path, "r") if f then f:close() return true end return false end
function File.GetFiles(dir, ext)
  local result = {}
  local p = io.popen("ls '" .. dir .. "' 2>/dev/null")
  for line in p:lines() do if line:sub(-#ext) == ext then result[#result + 1] = dir .. "/" .. line end end
  p:close()
  return result
end
ConsoleOutput = {}
Console = {
  Log = function(fmt, ...) ConsoleOutput[#ConsoleOutput + 1] = string.format(fmt, ...) end,
  RegisterCommand = function(name, callback) Console.commands = Console.commands or {} Console.commands[name] = callback end
}

Timers = {}
Timer = {
  SetTimeout = function(callback, ms) Timers[#Timers + 1] = { callback = callback, ms = ms } return #Timers end,
  ClearTimeout = function(id) if Timers[id] then Timers[id].cleared = true end end
}
function fireTimers()
  for _, t in ipairs(Timers) do if not t.cleared and not t.fired then t.fired = true t.callback() end end
end
