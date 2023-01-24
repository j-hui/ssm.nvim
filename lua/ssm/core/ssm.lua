---@diagnostic disable: unused-local
-- local priority = require("figet.core.priority")

-- need to implement:
-- self:call() -- done
-- self:spawn() -- done
-- self:wait() -- done
-- self:after() -- TODO

local sched = {}

function sched.logical_time()
  return 0
end

-- TID-indexed table of running processes
local proc_table = {}
local run_stack = require("ssm.core.Stack").Stack.New()
local run_queue = require("ssm.core.PriorityQueue").PriorityQueue.New()

function sched.get_process(tid)
  return proc_table[tid]
end

function sched.get_current()
  local tid, _ = coroutine.running()
  return sched.get_process(tid)
end

function sched.push_process(proc)
  assert(proc < run_stack:Peek(), "must only push higher priority process")
  run_stack:Push(proc)
end

function sched.enqueue_process(proc)
  run_queue:Add(proc, proc.prio)
end

--- Dequeue highest priority process scheduled to run.
function sched.next_process()
  if run_stack:IsEmpty() then
    return run_queue:Pop()
  end

  if run_stack:Peek() < run_queue:Peek() then
    -- run_stack:Peek() has higher priority
    return run_stack:Pop()
  else
    --- run_queue:Peek() has higher priority
    return run_queue:Pop()
  end
end

local channel = {}

local Channel = {}
Channel.__index = Channel
channel.Channel = Channel

function channel.is_channel(o)
  -- Channels are objects whose metatable is Channel
  return getmetatable(o) == Channel
end

function Channel:new(obj_val)
  local chan = {
    _value = {},
    _last = {},
    _later = {},
    _triggers = {},
    __index = channel.get,
    __newindex = channel.set,
  }

  for k, v in pairs(obj_val) do
    chan._value[k], chan._last[k] = v, sched.logical_time()
  end

  setmetatable(chan, self)
  chan._object = setmetatable({}, chan)
  return chan
end

function channel.new(obj_val)
  return Channel:new(obj_val)._object
end

function Channel:get(k)
  return self._value[k]
end

function channel.get(o, k)
  getmetatable(o):get(k)
end

function Channel:set(k, v)
  self._value[k], self._last[k] = v, sched.logical_time()

  local cur = sched.get_current()

  -- Accumulator for processes not triggered
  local remaining = {}

  for p, e in pairs(self._triggers) do
    if cur < p and (e == true or e[k] == true) then
      -- Enqueue any lower priority process that is sensitized to:
      -- (1) any update to self._object or (2) updates to self._object[k]
      sched.enqueue_process(p)
    else
      -- Processes not enqueued for execution remain sensitive
      remaining[p] = e
    end
  end

  self._triggers = remaining
end

function channel.set(o, k, v)
  getmetatable(o):set(k, v)
end

function Channel:last(k)
  if k == nil then
    -- Look for latest last-updated time on any key
    local t = 0
    for _, v in pairs(self._last) do
      t = math.max(t, v)
    end
    return t
  else
    -- Look for last-updated time on k
    return self.last[k]
  end
end

function channel.last(o, k)
  getmetatable(o):last(k)
end

function Channel:sensitize(p, k)
  if k == nil then
    -- p is notified for any update to self._object

    -- Even if there was already an entry, we can just overwite it with
    -- a catch-all entry.
    self._triggers[p] = true
  else
    -- p is notified for updates to self._object[k]

    if self._triggers[p] then
      -- There is already a _triggers entry for p; update it.

      if self._triggers[p] ~= true then
        -- p is only sensitized on updates to certain keys of self._object;
        -- add sub-entry for k.
        self._triggers[p][k] = true
      end
    else
      -- p is not yet sensitized for updates to self._object;
      -- need to create _triggers entry.

      self._triggers[p] = { k = true }
    end
  end
end

function channel.sensitize(o, p, k)
  getmetatable(o):sensitize(p, k)
end

function Channel:desensitize(p)
  self._triggers[p] = nil
end

function channel.desensitize(o, p)
  getmetatable(o):desensitize(p)
end

function Channel:after(d, k, v)
  self.later[k] = { d, v }
  -- TODO: schedule for later
end

function channel.after(o, d, k, v)
  getmetatable(o):after(d, k, v)
end
