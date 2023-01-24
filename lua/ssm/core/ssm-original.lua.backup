local priority = require("figet.core.priority")

local c = coroutine.create(function() end)
c:resume()

---@type thread
local t
t:status()

---@alias Time number

---@class Process
--- An execution context
---@field time Time: the current of execution
---@field priority Priority: the priority of the execution context
---@field continuation thread: where to return to in an execution context
---@field deferred Process[]: processes to be executed, created by par
local Process = {}
Process.__index = Process

---@type Process
local current

function Process:new(time, prio, func, args)
  local obj = {
    time = time,
    priority = prio,
    continuation = coroutine.create(function()
      func(unpack(args))
    end),
  }
  setmetatable(obj, self)
  return obj
end

function Process:resume(time)
  local cur = current
  current = self
  self.time = time or self.time
  self.continuation:resume()
  current = cur
end

function Process:yield()
  for p in ipairs(self.deferred) do
    p:resume()
  end
  coroutine.yield()
end

function Process:enter()
  current = self
  -- The following messes around with the function environment, and might enable
  -- some pretty funky programming models.
  --
  -- local env = { current = self }
  -- setmetatable(env, { __index = _G})
  -- setfenv(2, env)
end

---@class Routine
--- A routine consists of code that can be spawned into a process.
---
local Routine = {}
Routine.__index = {}

--- Spawn a process with higher priority than current process.
---@return SV: handle for communicating with caller
function Routine:seq(...)
  local callee = Process:new(current.time, current.priority)
  current.priority = current.priority:insert()
  coroutine.yield()
end

--- Spawn a process with lower priority than current process.
---@return SV: handle for communicating with forker
function Routine:par(...)
  local callee = Process:new(current.time, current.priority:insert())
end

---@class Event
--- An event is a value-timestamp pair.
---@field value any: value of the event
---@field time Time: the time of the event
---@field priority Priority: priority of the context where the event is created
local Event = {}
Event.__index = Event

function Event:new(v, t, p)
  local obj = {
    value = v,
    time = t or current.time,
    priority = p or current.priority,
  }
  setmetatable(obj, self)
  return obj
end

function Event.__le(a, b)
  if a.time == b.time then
    return a.priority <= b.priority
  else
    return a.time <= b.priority
  end
end

function Event.__lt(a, b)
  return a <= b and not (b <= a)
end

function Event.__eq(a, b)
  return a <= b and b <= a
end

---@class SV A scheduled variable.
---@field current Event: the current value and timestamp of the variable
---@field later table[Time]Event: local queue of scheduled assignments
---@field triggers any: list of processes to wake up when variable is assigned
local SV = {}
SV.__index = SV

function SV:new(v)
  local obj = {
    current = Event:new(v),
    later = {},
    triggers = {}, -- a set of contexts to return to
  }
  setmetatable(obj, self)
  return obj
end

function SV:get()
  return self.current.value, self.current.time
end

function SV:set(v)
  self.current = Event:new(v)
  -- TODO: schedule triggers
end

function SV:later(v, t)
  local later_event = Event:new(v, t)
  if self.later[t] then
    if later_event > self.later[t] then
      -- scheduled event with lower priority wins
      -- TODO: but is this the right way to resolve this conflict?
      self.later[t] = later_event
    end
  else
    self.later[t] = later_event
    -- TODO: register self on event queue
  end
end

function SV:after(d, v)
  assert(d > 0, "delay must be positive")
  self:later(v, current.time + d)
end

local SSM = {}
SSM.__index = SSM

function SSM:now()
  return current.time
end

function SSM:wait(...) end

function SSM:fork(...) end

function SSM:add2(a)
  a:set(a:get() + 2)
end

function SSM:mult4(a)
  a:set(a:get() * 4)
end

function SSM:main()
  local a = SV:new(1)

  self:fork(self:add2(a), self:mult4(a))

  print(a:get()) -- 3 * 4 = 12

  a:set(1)

  self:fork(self:mult4(a), self:add2(a))

  print(a:get()) -- 4 + 2 = 6

  a:after(3, 3)

  self:wait(a)

  self:mult4(a).call()
end

-- function SSM:main()
--   local a = SV:new(1)
--
--   fork(add2(a), mult4(a))
--
--   print(a:get()) -- 3 * 4 = 12
--
--   a:set(1)
--
--   call(mult4(a), add2(a))
--
--   print(a:get()) -- 4 + 2 = 6
--
--   a:after(3, 3)
--
--   wait(a)
--
--   call(mult4(a))
-- end
