--- Internal implementation of the SSM library

local M = {}

local dbg = require("ssm.dbg")
local Priority = require("ssm.Priority")
local PriorityQueue = require("ssm.PriorityQueue")
local Stack = require("ssm.Stack")

--- ipairs(), except starting from the given index.
---@param t   any[]                                 Array to iterate over
---@param s   number                                Start index
---@return    fun(a: any[], i: number): (any|nil)   The stateless iterator
---@return    any[]                                 The array to iterate over
---@return    number                                Start index - 1
local function ipairs_from(t, s)
  local function iter(a, i)
    i = i + 1
    local v = a[i]
    if v then
      return i, v
    end
  end

  return iter, t, s - 1
end

--- For compatability between Lua 5.1 and 5.2/5.3/5.4
---@diagnostic disable-next-line: deprecated
local table_unpack = table.unpack or unpack

----[[ Timestamps and durations ]]----

local Time = {}
M.Time = Time

---@class Duration: integer
---@operator add(LogicalTime): LogicalTime
---@operator add(PhysicalTime): PhysicalTime
---
---@class Timestamp: integer|false
---
---@class LogicalTime: Timestamp
---@operator add(Duration): LogicalTime
---@alias Time LogicalTime
---
---@class PhysicalTime: Timestamp
---@operator add(Duration): PhysicalTime

--- Bottom element of logical timestamps.
---@type Time
Time.NEVER = nil

--- Return the minimum of two timestamps.
---
---@generic T: Timestamp
---@param l T
---@param r T
---@return  T
function Time.min(l, r)
  if l == M.NEVER then
    return r
  elseif r == M.NEVER then
    return l
  else
    return math.min(l, r)
  end
end

--- Whether a timestamp is greater than another.
---
---@generic T: Timestamp
---@param l T
---@param r T
---@return  boolean
function Time.lt(l, r)
  if l == M.NEVER then
    return false
  elseif r == M.NEVER then
    return true
  else
    return l < r
  end
end

--- Current logical time
---@type Time
local current_time = 0


----[[ Scheduler state and decision-making ]]----

--- Process table
---@type table<thread, Process>
local proc_table = {}

--- Stack of queued processes (head has the highest priority).
-- @type Stack<Process>
local run_stack = Stack()

--- Priority queue of processes to run.
-- @type PriorityQueue<Process>
local run_queue = PriorityQueue()

--- Priority queue for delayed update events to channel tables.
-- @type PriorityQueue<Channel>
local event_queue = PriorityQueue()

--- Number of active processes. When this hits zero, it's time to stop.
local num_active = 0

--- Add a process to the process table, indexed by its thread identifier.
---
---@param proc Process  The process to add.
local function register_process(proc)
  proc_table[proc.cont] = proc
end

--- Remove an indexed process from the process table.
---
---@param tid thread The thread identifier in the process table.
local function unregister_process(tid)
  proc_table[tid] = nil
end

--- Obtain process structure for currently running coroutine thread.
---
---@return  Process         The current process structure.
function M.get_current_process()
  return proc_table[coroutine.running()]
end

--- Add a process structure to the run stack.
---
--- p must have a higher priority than what is at the top of the stack.
---
---@param p Process   Process structure to be queued.
local function push_process(p)
  if p.scheduled then
    return
  end

  p.scheduled = true

  local old_head = run_stack:peek()
  if old_head then
    assert(p < old_head, "Can only push higher priority process")
  end

  run_stack:push(p)
end

--- Add a process structure to the run queue.
---
---@param p Process   Process structure to be queued.
local function enqueue_process(p)
  if p.scheduled then
    return
  end

  p.scheduled = true

  run_queue:add(p, p.prio)
end

--- Obtain the process structure for the process scheduled to run next.
---
---@return Process|nil  Process structure to run next.
local function dequeue_next()
  local p

  if run_stack:is_empty() then
    -- runStack is empty
    p = run_queue:pop()
  elseif run_queue:size() == 0 then
    -- runQueue is empty
    p = run_stack:pop()
  elseif run_stack:peek() < run_queue:peek() then
    -- runStack has higher priority
    p = run_stack:pop()
  else
    --- runQueue has higher priority
    p = run_queue:pop()
  end

  if p ~= nil then
    p.scheduled = false
  end

  return p
end

local function schedule_event(chan)
  if chan.scheduled then
    event_queue:reposition(chan, chan) -- TODO: replace with chan.earliest
  else
    chan.scheduled = true
    event_queue:add(chan, chan) -- TODO: replace with chan.earliest
  end
end

local function dequeue_event_at(t)
  ---@type Channel|nil
  local chan = event_queue:peek()

  if t == Time.NEVER or chan == nil or chan.earliest ~= t then
    return nil
  end

  event_queue:pop() -- NOTE: result of Pop() is same as c
  chan.scheduled = false
  return chan
end

local function num_active_inc()
  num_active = num_active + 1
end

local function num_active_dec()
  num_active = num_active - 1
end

---- [[ Channels ]] ----

---@class CTable: table
---@alias Key any
---@alias IsSched true|table<Key, true>
---@alias Event {[1]: Time, [2]: any}

---@class Channel
---
---@field public  table     CTable                Table attached
---@field package value     table<Key, any>       Current value
---@field package last      table<Key, Time>      Last modified time
---@field package later     table<Key, Event>     Delayed update events
---@field public  earliest  Time                  Earliest scheduled update
---@field package triggers  table<Process, true>  What to run when updated
---@field package scheduled boolean               Whether this is scheduled
---@field private name string TODO: debugging
local Channel = {}
Channel.__index = Channel

function Channel:__tostring()
  -- FIXME: for debugging
  return self.name
end

--- Obtain the Channel metatable of a channel table.
---
---@param tbl CTable
---@return    Channel
local function table_get_channel(tbl)
  return getmetatable(tbl)
end

--- See if a table has a channel attached ot it.
---
---@param o   table     The table to check.
---@return    boolean   Whether o has a channel attached.
local function table_has_channel(o)
  return getmetatable(table_get_channel(o)) == Channel
end

--- Getter for channel tables.
---
---@param tbl CTable
---@param k   Key
---@return    any
local function channel_getter(tbl, k)
  return table_get_channel(tbl).value[k]
end

--- Setter for channel tables; schedules sensitive lower priority processes.
---
--- If v is nil (i.e., the caller is deleting the field k), the corresponding
--- last field is also deleted.
---
---@param tbl CTable
---@param k   Key
---@param v   any
local function channel_setter(tbl, k, v)
  local self = table_get_channel(tbl)

  dbg("Assignment to channel happened: " .. tostring(self))

  local t = v == nil and nil or current_time
  self.value[k], self.last[k] = v, t

  local cur = M.get_current_process()

  -- Accumulator for processes not triggered
  local remaining = {}

  for p, _ in pairs(self.triggers) do
    if cur < p then
      enqueue_process(p)
    else
      -- Processes not enqueued for execution remain sensitive.
      remaining[p] = true
    end
  end

  self.triggers = remaining
end

local function channel_pairs(tbl)
  local self = table_get_channel(tbl)
  local f = pairs(self.value)
  return f, tbl, nil
end

local function channel_ipairs(tbl)
  local self = table_get_channel(tbl)
  local f = ipairs(self.value)
  return f, tbl, nil
end

local function channel_len(tbl)
  local self = table_get_channel(tbl)
  return #self.value
end

--- Construct a new Channel whose table is initialized with init.
---
---@param init    table     The table to initialize the channel's value with.
---@return        Channel   The newly constructed Channel.
local function channel_new(init)
  local chan = {
    value = {},
    later = {},
    last = {},
    earliest = Time.NEVER,
    triggers = {},
    __index = channel_getter,
    __newindex = channel_setter,
    __pairs = channel_pairs,
    __ipairs = channel_ipairs,
    __len = channel_len,
    name = "c" .. dbg.fresh(),
  }

  function chan.__tostring()
    return chan.name .. ".table"
  end

  local now = current_time

  for k, v in pairs(init) do
    chan.value[k], chan.last[k] = v, now
  end

  chan.table = setmetatable({}, chan)

  setmetatable(chan, Channel)
  return chan
end

--- Comparator for Channels.
---
---@param l Channel
---@param r Channel
---@return boolean
function Channel.__lt(l, r)
  return Time.lt(l.earliest, r.earliest)
end

--- Perform delayed update on a channel table, and schedule sensitive processes.
---
---@param self Channel
local function channel_do_update(self)
  local next_earliest = Time.NEVER

  assert(self.earliest == current_time, "Updating at the right time")
  local updated_keys = {}

  for k, e in pairs(self.later) do
    local t, v = e[1], e[2]

    if t == self.earliest then
      self.value[k], self.last[k] = v, t
      self.later[k] = nil
      table.insert(updated_keys, k)
    else
      assert(Time.lt(self.earliest, t), "Updates are taking place out of order??")
      next_earliest = Time.min(next_earliest, t)
    end
  end

  self.earliest = next_earliest

  for p, _ in pairs(self.triggers) do
    enqueue_process(p)
  end

  self.triggers = {}
end

--- Sensitize a process to updates on a channel table.
---
--- If p was already sensitized to any updates to tbl, this method does nothing.
---
---@param tbl CTable    The channel table to be sensitized to.
---@param p   Process   The process to sensitize.
local function channel_sensitize(tbl, p)
  local self = table_get_channel(tbl)

  dbg("Sensitizing " .. tostring(p) .. " to updates to " .. tostring(self))
  -- p is notified for any update to self.table

  -- Even if there was already an entry, we can just overwite it with
  -- a catch-all entry.
  self.triggers[p] = true
end

--- Remove the trigger for a process, desensitizing it from updates to tbl.
---@param tbl CTable    The channel table to be desensitized from.
---@param p   Process   The process to desensitize.
local function channel_desensitize(tbl, p)
  local self = table_get_channel(tbl)
  dbg("desensitizing from updates to: " .. tostring(self))
  self.triggers[p] = nil
end

--- Scheduld a delayed update to a channel table.
---
---@param tbl CTable    The channel table to schedule an update to.
---@param t   Time      How far in the future to schedule an update for.
---@param k   Key       The key to at which the delayed update is scheduled.
---@param v   any       The value to update k with.
local function channel_schedule_update(tbl, t, k, v)
  local self = table_get_channel(tbl)

  self.later[k] = { t, v }
  self.earliest = Time.min(self.earliest, t)

  schedule_event(self)
end

--- Construct a new table with an attached channel.
---
---@param init  table   The table to initialize the channel's value with.
---@return      CTable  The newly constructed channel table.
function M.make_channel_table(init)
  return channel_new(init).table
end

--- Obtain the last time a channel table (or one of its field) was modified.
---
--- If k is nil, this method will return the earliest timestamp among all
--- the table's fields.
---
--- If there no value indexed by k, this method returns nil.
---
---@param tbl CTable    The channel table.
---@param k   Key|nil   The key of tbl.
---@return    Time|nil  Logical timestamp of last modification, if any.
function M.channel_last_updated(tbl, k)
  local self = table_get_channel(tbl)

  if k == nil then
    -- Look for latest last-updated time on any key
    local t = 0
    for _, v in pairs(self.last) do
      t = math.max(t, v)
    end
    return t
  else
    -- Look for last-updated time on k.
    return self.last[k]
  end
end

---- [[ Processes ]] ----

---@class Process
---
--- Object to store metadata for running thread. Also the subject of self within
--- SSM routines; methods attached to Processes are part of SSM's public API.
---
---@field package cont      thread
---@field package prio      Priority
---@field private chan      Channel
---@field private name      string
---@field private active    boolean
---@field package scheduled boolean
local Process = {}
Process.__index = Process

function Process:__tostring()
  return self.name
end

--- Construct a new Process.
---
---@param func  fun(any): any   Function to execute in process.
---@param args  any[]           Table of arguments to routine.
---@param rtbl  CTable|nil      Process status channel.
---@param prio  Priority        Priority of the process.
---@return      Process         The newly constructed process.
local function process_new(func, args, rtbl, prio)
  local proc = { rtbl = rtbl, prio = prio, active = true, name = "p" .. dbg.fresh() }

  -- proc becomes the self of func
  proc.cont = coroutine.create(function()
    local function pdbg(...)
      dbg("Process: " .. tostring(proc), ...)
    end

    pdbg("Created proc for function: " .. tostring(func),
      "Termination channel: " .. tostring(proc.rtbl))

    local r = { func(proc, table_unpack(args)) }

    -- Set return values
    if proc.rtbl then
      for i, v in ipairs(r) do
        pdbg("Terminated.", "Assigning return value: [" .. tostring(i) .. "] " .. tostring(v))
        proc.rtbl[i] = v
      end

      -- Convey termination
      pdbg("Terminated.", "Assigning to termination channel (" .. tostring(proc.rtbl) .. ")")
      proc.rtbl.terminated = true
    else
      pdbg("Terminated. No termination channel.")
    end

    -- Decrement activity count
    if proc.active then
      num_active_dec()
      proc.active = false
    end

    -- Delete process from process table
    unregister_process(proc.cont)

    pdbg("Unregistered process")
  end)

  setmetatable(proc, Process)

  register_process(proc)
  num_active_inc()

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

  local rtbl = M.make_channel_table({ terminated = false })

  -- Give the new process our current priority; give ourselves a new priority,
  -- immediately afterwards.
  local prio = self.prio
  self.prio = self.prio:insert()

  push_process(self)
  push_process(process_new(func, args, rtbl, prio))

  coroutine.yield()

  return rtbl
end

function Process:spawn(func, ...)
  local args = { ... }
  local chan = M.make_channel_table({ terminated = false })
  local prio = self.prio:insert()

  push_process(process_new(func, args, chan, prio))

  return chan
end

function Process:wait(...)
  local wait_specs = { ... }

  dbg(tostring(self) .. ": waiting on " .. tostring(#wait_specs) .. " channels")

  if #wait_specs == 0 then
    return
  end

  for i, tbl in ipairs(wait_specs) do
    dbg("Argument: " .. tostring(i) .. "->" .. tostring(tbl))
    channel_sensitize(tbl, self)
  end

  dbg(tostring(self) .. ": about to yield due to wait")
  coroutine.yield()
  dbg(tostring(self) .. ": returned from yield due to wait")

  -- Desensitize from all objects
  for _, tbl in ipairs(wait_specs) do
    channel_desensitize(tbl, self)
  end
end

--- Schedule a delayed update on a channel.
---
---@param d Duration  How long after now to perform update.
---@param t table     Table to perform update on.
---@param k any       Key of t to perform update on.
---@param v any       Value to assign to t[k].
function Process:after(d, t, k, v)
  channel_schedule_update(t, current_time + d, k, v)
end

--- Obtain the current logical time.
---
---@return LogicalTime
function Process:now()
  return current_time
end

function Process:set_active()
  if not self.active then
    num_active_inc()
    self.active = true
  end
end

function Process:set_passive()
  if self.active then
    num_active_dec()
    self.active = false
  end
end

--- Resume execution of a process.
---@param p Process
local function process_resume(p)
  local ok, err = coroutine.resume(p.cont)
  if not ok then
    print(err)
    print(debug.traceback(p.cont))
  end
end

---- [[ Tick loop ]] ----

--- Iterator for scheduled processes; dequeues them from run queue and stack.
---
---@return fun(): (Process|nil)   Called every iteration to dequeue next process
---@return nil                    Unused
---@return nil                    Unused
local function scheduled_processes()
  return dequeue_next, nil, nil
end

--- Iterator for events scheduled at the current instant; dequeues them.
---
---@return fun(): (Channel|nil)   Called every iteration to dequeue next event
---@return LogicalTime            Which instant to dequeue events for
---@return nil                    Unused
local function scheduled_events()
  return dequeue_event_at, M.next_update_time(), nil
end

function M.num_active()
  return num_active
end

function M.next_update_time()
  ---@type Channel|nil
  local c = event_queue:peek()
  if c == nil then
    return Time.NEVER
  end
  return c.earliest
end

--- Get the current logical time.
---
---@return          LogicalTime   The current time
function M.current_time()
  return current_time
end

--- Advance time to a certain point in the future.
---
--- Time must strictly advance monotonically.
---
---@param next_time LogicalTime   What time to advance to
---@return          LogicalTime   The previous timestamp
function M.set_time(next_time)
  if current_time == Time.NEVER and next_time == Time.NEVER then
    return Time.NEVER
  end

  assert(Time.lt(current_time, next_time), "Time must advance forwards")

  current_time = next_time
  return current_time
end

function M.run_instant()
  for c in scheduled_events() do
    channel_do_update(c)
  end

  for p in scheduled_processes() do
    process_resume(p)
  end
end

function M.spawn_root_process(f, args)
  local chan = M.make_channel_table({ terminated = false })
  push_process(process_new(f, args or {}, chan, Priority()))
  return chan
end

return M
