local M = {}

local Time = require("ssm.core.Time")

--- Process table
---@type table<thread, Process>
local procTable = {}

--- Stack of queued processes (head has the highest priority).
-- @type Stack<Process>
local runStack = require("ssm.core.Stack").Stack.New()

--- Priority queue of processes to run.
-- @type PriorityQueue<Process>
local runQueue = require("ssm.core.PriorityQueue").PriorityQueue.New()

--- Whether a process is scheduled.
---@type table<Process, true>
local runScheduled = {}

--- Priority queue for delayed update events to channel tables.
-- @type PriorityQueue<Channel>
local eventQueue = require("ssm.core.PriorityQueue").PriorityQueue.New()

--- Whether a Channel's update event is scheduled.
---@type table<Channel, true>
local eventScheduled = {}

--- Add a process to the process table, indexed by its thread identifier.
---
---@param proc Process  The process to add.
function M.registerProcess(proc)
  procTable[proc.cont] = proc
end

--- Remove an indexed process from the process table.
---
---@param tid thread The thread identifier in the process table.
function M.unregisterProcess(tid)
  procTable[tid] = nil
end

--- Obtain process structure indexed by a coroutine thread.
---
---@param   tid     thread  Thread identifier of a coroutine thread.
---@return  Process         The indexed process structure (if any).
function M.getProcess(tid)
  return procTable[tid]
end

--- Obtain process structure for currently running coroutine thread.
---
---@return  Process         The current process structure.
function M.getCurrent()
  return M.getProcess(coroutine.running())
end

--- Add a process structure to the run stack.
---
--- p must have a higher priority than what is at the top of the stack.
---
---@param p Process   Process structure to be queued.
function M.pushProcess(p)
  if runScheduled[p] then
    return
  end

  runScheduled[p] = true

  local oldHead = runStack:Peek()
  if oldHead then
    assert(p < oldHead, "Can only push higher priority process")
  end

  runStack:Push(p)
end

--- Add a process structure to the run queue.
---
---@param p Process   Process structure to be queued.
function M.enqueueProcess(p)
  if runScheduled[p] then
    return
  end

  runScheduled[p] = true

  runQueue:Add(p, p.prio)
end

--- Obtain the process structure for the process scheduled to run next.
---
---@return Process|nil  Process structure to run next.
local function dequeueNext()
  local p

  if runStack:IsEmpty() then
    -- runStack is empty
    p = runQueue:Pop()
  elseif runQueue:Size() == 0 then
    -- runQueue is empty
    p = runStack:Pop()
  elseif runStack:Peek() < runQueue:Peek() then
    -- runStack has higher priority
    p = runStack:Pop()
  else
    --- runQueue has higher priority
    p = runQueue:Pop()
  end

  if p ~= nil then
    runScheduled[p] = nil
  end

  return p
end

function M.ScheduledProcesses()
  return dequeueNext
end

function M.ScheduleEvent(chan)
  if eventScheduled[chan] then
    eventQueue:Reposition(chan, chan) -- TODO: replace with chan.earliest
  else
    eventScheduled[chan] = true
    eventQueue:Add(chan, chan) -- TODO: replace with chan.earliest
  end
end

local function dequeueEventAt(t)
  ---@type Channel|nil
  local c = eventQueue:Peek()

  if t == Time.NEVER or c == nil or c.earliest ~= t then
    return nil
  end

  eventQueue:Pop() -- NOTE: result of Pop() is same as c
  return c
end

function M.NextUpdateTime()
  ---@type Channel|nil
  local c = eventQueue:Peek()
  if c == nil then
    return Time.NEVER
  end
  return c.earliest
end

function M.ScheduledEvents()
  return dequeueEventAt, M.NextUpdateTime(), nil
end

local currentTime = 0

--- Advance the current logical timestamp; return old and the new timestamps.
---
---@return Time
function M.AdvanceTime()
  local nextTime = M.NextUpdateTime()
  if nextTime == Time.NEVER then
    return Time.NEVER
  end

  assert(Time.lt(currentTime, nextTime), "Time must advance forwards")

  currentTime = nextTime
  return currentTime
end

--- Get the current logical timestamp
---
---@return Time
function M.LogicalTime()
  return currentTime
end

return M
