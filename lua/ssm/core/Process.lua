local M = {}

local sched = require("ssm.core.sched")
local Channel = require("ssm.core.Channel")

---@class Process
---
--- Object to store metadata for running thread. Also the subject of self within
--- SSM routines.
---
---@field cont thread
---@field prio Priority
---@field chan Channel
local Process = {}
Process.__index = Process

M.Process = Process

--- Construct a new Process.
---
---@param func  fun(any): any   Function to execute.
---@param args  any[]           Table of arguments to routine.
---@param chan  Channel         Process status channel.
---@param prio  Priority        Priority of the process.
---@return      Process         The newly constructed process.
function Process.new(func, args, chan, prio)
  local proc = { chan = chan, prio = prio }

  -- proc becomes the self of func
  proc.cont = coroutine.create(function()
    local r = { func(proc, unpack(args)) }

    -- Set return values
    for i, v in ipairs(r) do
      Channel.getTable(chan)[i] = v
    end

    -- Convey termination
    Channel.getTable(chan).terminated = true

    -- Delete process from process table.
    sched.unregisterProcess(proc.cont)
  end)

  setmetatable(proc, Process)

  sched.registerProcess(proc)

  return proc
end

--- Processes are compared according to their priorities.
---
---@param self  Process
---@param other Process
---@return      boolean
function Process.__lt(self, other)
  return self.prio < other.prio
end

function Process:call(func, ...)
  local args = { ... }

  local chan = Channel.Channel.new({ terminated = false })

  -- Give the new process our current priority; give ourselves a new priority,
  -- immediately afterwards.
  local prio = self.prio
  self.prio = self.prio:Insert()

  local proc = Process.new(func, args, chan, prio)

  sched.registerProcess(proc)
  sched.pushProcess(self)
  sched.pushProcess(proc)
  coroutine.yield()
end

function Process:spawn(func, ...)
  local args = { ... }
  local chan = Channel.Channel.new({ terminated = false })
  local prio = self.prio:Insert()

  local proc = Process.new(func, args, chan, prio)

  sched.registerProcess(proc)
  sched.pushProcess(proc)
end

--- A lil stateless iterator.
---
---@param a any[]   What to iterate over.
---@param i integer The 0-indexed index for iteration.
local function iiter(a, i)
  i = i + 1
  local v = a[i]
  if v then
    return i, v
  end
end

function Process:wait(...)
  local os = { ... }

  for _, o in ipairs(os) do
    if Channel.is_channel(o) then
      -- self:wait(..., o, ...), where o is a Channel object,
      -- i.e., wait on any update to o.
      Channel.sensitize(o, self)
    else
      -- self:wait(..., {o, k1 ... kn}, ...), where o is a Channel object and
      -- k1 ... kn are keys, i.e., wait on updates to o[k1] ... o[kn].
      for _, k in iiter, o, 1 do
        Channel.sensitize(o[1], self, k)
      end
    end
  end

  coroutine.yield()

  -- Desensitize from all objects
  for _, o in ipairs(os) do
    if Channel.is_channel(o) then
      Channel.desensitize(o, self)
    else
      Channel.desensitize(o[1], self)
    end
  end
end

--- Schedule a delayed update on a channel.
---
---@param d Duration  How long after now to perform update.
---@param t table     Table to perform update on.
---@param k any       Key of t to perform update on.
---@param v any       Value to assign to t[k].
function Process:after(d, t, k, v)
  Channel.after(t, d, k, v)
end

--- Resume execution of a process.
---@param p Process
function M.resume(p)
  coroutine.resume(p.cont)
end

return M
