local M = {}

local sched = require("ssm.core.sched")
local Channel = require("ssm.core.Channel")
local Priority = require("ssm.core.Priority")
local dbg = require("ssm.core.dbg")

---@class Process
---
--- Object to store metadata for running thread. Also the subject of self within
--- SSM routines.
---
---@field package cont thread
---@field package prio Priority
---@field package chan Channel
---@field private name string
local Process = {}
Process.__index = Process

function Process:__tostring()
  return self.name
end

--- Construct a new Process.
---
---@param func  fun(any): any   Function to execute in process.
---@param args  any[]           Table of arguments to routine.
---@param chan  Channel|nil     Process status channel.
---@param prio  Priority        Priority of the process.
---@return      Process         The newly constructed process.
local function newProcess(func, args, chan, prio)
  local proc = { chan = chan, prio = prio, name = "p" .. dbg.fresh() }

  -- proc becomes the self of func
  proc.cont = coroutine.create(function()
    local function pdbg(...)
      dbg("Process: " .. tostring(proc), ...)
    end

    pdbg("Created proc for function: " .. tostring(func),
      "Termination channel: " .. tostring(proc.chan))

    local r = { func(proc, unpack(args)) }


    if proc.chan then

      for i, v in ipairs(r) do
        pdbg("Terminated.", "Assigning return value: [" .. tostring(i) .. "] " .. tostring(v))
        proc.chan[i] = v
      end

      -- Convey termination
      pdbg("Terminated.", "Assigning to termination channel (" .. tostring(proc.chan) .. ")")
      proc.chan.terminated = true
    else
      pdbg("Terminated. No termination channel.")
    end

    -- Set return values
    -- Delete process from process table.
    sched.unregisterProcess(proc.cont)

    pdbg("Unregistered process")
  end)

  setmetatable(proc, Process)

  sched.registerProcess(proc)
  sched.pushProcess(proc)

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

--- Create a new process at the start of the process hierarchy.
---
---@param func  fun(any): any   Function to execute in process.
---@param args  any[]           Table of arguments to routine.
function M.Start(func, args)
  newProcess(func, args, nil, Priority.New())
end

function Process:call(func, ...)
  local args = { ... }

  local chan = Channel.New({ terminated = false })

  -- Give the new process our current priority; give ourselves a new priority,
  -- immediately afterwards.
  local prio = self.prio
  self.prio = self.prio:Insert()

  sched.pushProcess(self)
  newProcess(func, args, chan, prio)
  coroutine.yield()

  return chan
end

function Process:spawn(func, ...)
  local args = { ... }
  local chan = Channel.New({ terminated = false })
  local prio = self.prio:Insert()

  newProcess(func, args, chan, prio)

  return chan
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
  local ts = { ... }

  dbg(tostring(self) .. ": waiting on " .. tostring(#ts) .. " channels")
  for k, t in pairs(ts) do
    dbg("Argument: " .. tostring(k) .. "->" .. tostring(t))

    if Channel.HasChannel(t) then
      -- self:wait(..., t, ...), where t: CTable; i.e., wait on any update to t.
      Channel.Sensitize(t, self)
    else
      -- self:wait(..., {t, k1 ... kn}, ...), where t: CTable and
      -- k1 ... kn are keys, i.e., wait on updates to o[k1] ... o[kn].
      for _, k in iiter, t, 1 do
        Channel.Sensitize(t[1], self, k)
      end
    end
  end

  dbg(tostring(self) .. ": about to yield due to wait")
  coroutine.yield()
  dbg(tostring(self) .. ": returned from yield due to wait")

  -- Desensitize from all objects
  for _, t in ipairs(ts) do
    if Channel.HasChannel(t) then
      Channel.Desensitize(t, self)
    else
      Channel.Desensitize(t[1], self)
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
  Channel.After(t, d, k, v)
end

function Process:now()
  return sched.LogicalTime()
end

--- Resume execution of a process.
---@param p Process
function M.Resume(p)
  local ok, err = coroutine.resume(p.cont)
  if not ok then
    print(err)
    print(debug.traceback())
  end
end

return M
