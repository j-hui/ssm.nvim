--- Internal implementation of the SSM library
local M = {}

local dbg = require("ssm.dbg")
local Priority = require("ssm.Priority")
local PriorityQueue = require("ssm.PriorityQueue")
local Stack = require("ssm.Stack")

--- For compatability between Lua 5.1 and 5.2/5.3/5.4
---@diagnostic disable-next-line: deprecated
local table_unpack = table.unpack or unpack

----[[ Timestamps and durations ]]----

---@class Duration: integer
---@operator add(LogicalTime): LogicalTime
---@operator add(PhysicalTime): PhysicalTime
---
---@class Timestamp: number
---FIXME: "inheriting" from number doesn't seem to work...
---
---@class LogicalTime: Timestamp
---@operator add(Duration): LogicalTime
---@alias Time LogicalTime
---
---@class PhysicalTime: Timestamp
---@operator add(Duration): PhysicalTime

--- Bottom element of logical timestamps.
local NEVER = math.huge

-- Silly cast to satisfy sumneko...
---@cast NEVER LogicalTime

--- Bottom element of logical timestamps.
---@type LogicalTime
M.NEVER = NEVER

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
---@return  Process         current_process
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
---@return Process|nil  next_process
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

--- Schedule a delayed update event for a channel.
---
---@param chan Channel
local function schedule_event(chan)
  if chan.scheduled then
    event_queue:reposition(chan, chan.earliest)
  else
    chan.scheduled = true
    event_queue:add(chan, chan.earliest)
  end
end

--- Dequeue a delayed update event at time t, if any.
---
---@param   t LogicalTime
---@return    Channel|nil maybe_channel
local function dequeue_event_at(t)
  ---@type Channel|nil
  local chan = event_queue:peek()

  if t == NEVER or chan == nil or chan.earliest ~= t then
    return nil
  end

  event_queue:pop() -- NOTE: result of pop() is same as c
  chan.scheduled = false
  return chan
end

--- Increment the number of processes considered active.
local function num_active_inc()
  num_active = num_active + 1
end

--- Decrement the number of processes considered active.
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

--- FIXME: this only exists for debugging
function Channel:__tostring()
  return self.name
end

--- Obtain the Channel metatable of a channel table.
---
---@param tbl CTable
---@return    Channel tbl_channel
local function table_get_channel(tbl)
  return getmetatable(tbl)
end

--- See if a table has a channel attached ot it.
---
---@param o   table     The table to check.
---@return    boolean   has_channel
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

--- Override for channel tables' __pairs() method.
---
---@generic K
---@generic V
---
---@param tbl table<K, V>   What to iterate over.
---@return fun(table: table<K, V>, i: integer|nil):K, V iterator
---@return table<K, V>                                  state
---@return nil                                          unused
local function channel_pairs(tbl)
  local self = table_get_channel(tbl)
  local f = pairs(self.value)
  return f, tbl, nil
end

--- Override for channel tables' __ipairs() method.
---
---@generic T
---
---@param tbl T[]           What to iterate over.
---@return fun(table: T[], i: integer|nil):integer, T   iterator
---@return T[]                                          state
---@return nil                                          unused
local function channel_ipairs(tbl)
  local self = table_get_channel(tbl)
  local f = ipairs(self.value)
  return f, tbl, nil
end

--- Override for channel tables' __len() method.
---
---@param   tbl     CTable  The channel table
---@return          integer length
local function channel_len(tbl)
  local self = table_get_channel(tbl)
  return #self.value
end

--- Construct a new Channel whose table is initialized with init.
---
---@param init    table     The table to initialize the channel's value with.
---@return        Channel   new_channel
local function channel_new(init)
  local chan = {
    value = {},
    later = {},
    last = {},
    earliest = NEVER,
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
---@return boolean result
function Channel.__lt(l, r)
  return l.earliest < r.earliest
end

--- Perform delayed update on a channel table, and schedule sensitive processes.
---
---@param self Channel
local function channel_do_update(self)
  local next_earliest = NEVER

  assert(self.earliest == current_time, "Updating at the right time")
  local updated_keys = {}

  for k, e in pairs(self.later) do
    local t, v = e[1], e[2]

    if t == self.earliest then
      self.value[k], self.last[k] = v, t
      self.later[k] = nil
      table.insert(updated_keys, k)
    else
      assert(self.earliest < t, "Updates are taking place out of order??")
      next_earliest = math.min(next_earliest, t)
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
  self.triggers[p] = true
end

--- Whether a process is sensitized to updates on a channel table.
---
---@param tbl CTable    The channel table to check.
---@param p   Process   The process to check sensitivity for
---@return    boolean   is_sensitized
local function channel_is_sensitized(tbl, p)
  local self = table_get_channel(tbl)
  return self.triggers[p] ~= nil
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
  self.earliest = math.min(self.earliest, t)

  schedule_event(self)
end

--- Construct a new table with an attached channel.
---
---@param init  table   The table to initialize the channel's value with.
---@return      CTable  channel_table
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
---@return    Time|nil  last_modification
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
---@return      Process         new_process
local function process_new(func, args, rtbl, prio)
  local proc = { rtbl = rtbl, prio = prio, active = true, name = "p" .. dbg.fresh() }

  -- proc becomes the self of func
  proc.cont = coroutine.create(function()
    local function pdbg(...)
      dbg("Process: " .. tostring(proc), ...)
    end

    pdbg("Created proc for function: " .. tostring(func),
      "return channel: " .. tostring(proc.rtbl))

    local r = { func(proc, table_unpack(args)) }

    -- Set return values
    if proc.rtbl then
      for i, v in ipairs(r) do
        pdbg("Terminated.", "Assigning return value: [" .. tostring(i) .. "] " .. tostring(v))
        proc.rtbl[i] = v
      end

      -- Convey termination
      pdbg("Terminated.", "Assigning to return channel (" .. tostring(proc.rtbl) .. ")")
      proc.rtbl.terminated = true
    else
      pdbg("Terminated. No return channel.")
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

--- Create a process from a function, at a higher priority than the caller.
---
--- The caller will suspend as the newly spawned process executes its inaugural
--- instant; the caller will resume execution in the same instant after the new
--- process waits or terminates.
---
---@generic T
---
---@param func  fun(T...)
---@param ...   T
---@return      CTable    return_channel
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

--- Create a process from a function, at a lower priority than the caller.
---
--- The newly spawned process will execute its inaugural instant after the
--- caller waits or terminates.
---
---@generic T
---
---@param func  fun(T...)
---@param ...   T
---@return      CTable    return_channel
function Process:spawn(func, ...)
  local args = { ... }
  local chan = M.make_channel_table({ terminated = false })
  local prio = self.prio:insert()

  push_process(process_new(func, args, chan, prio))

  return chan
end

--- Wait for updates on some number of channel tables.
---
--- Each argument is a "wait specification", which is either be a channel table
--- or an array of channel tables. A wait specification is satisfied when all
--- channel tables therein have been assigned to (not necessarily in the same
--- instant).
---
--- wait() unblocks when at least one wait specification is satisfied. It will
--- return multiple boolean return values, positionally indicating whether each
--- wait specification in the argument was satisfied.
---
--- In other words, wait(a, {b, c}) will unblock when a is updated, or both
--- b and c are updated.
---
--- TODO: reimplement without clobbering? And remove casts.
---
---@param   ... CTable|CTable[]   Wait specification
---@return      boolean ...       Whether that item unblocked
function Process:wait(...)
  local wait_specs = { ... }

  dbg(tostring(self) .. ": waiting on " .. tostring(#wait_specs) .. " channels")

  if #wait_specs == 0 then
    return
  end

  for i, wait_spec in ipairs(wait_specs) do
    if table_has_channel(wait_spec) then
      local tbl = wait_spec
      dbg("Argument: " .. tostring(i) .. "->" .. tostring(tbl))
      channel_sensitize(tbl, self)
    else
      for j, tbl in ipairs(wait_spec) do
        dbg("Argument: " .. tostring(i) .. "." .. tostring(j) .. "->" .. tostring(tbl))
        channel_sensitize(tbl, self)
      end
    end
  end

  ---@cast wait_specs (CTable|true|(CTable|true)[])[]

  local keep_waiting = true
  while keep_waiting do

    dbg(tostring(self) .. ": about to yield due to wait")
    coroutine.yield()
    dbg(tostring(self) .. ": returned from yield due to wait")

    -- At this point, all channel tables that this process is sensitive to have
    -- already removed this process from its sensitivity list (triggers).
    -- This process needs to iterate through and determine whether it is done
    -- waiting.

    for i, wait_spec in ipairs(wait_specs) do
      if wait_spec ~= true then
        if table_has_channel(wait_spec) then
          local tbl = wait_spec
          if not channel_is_sensitized(tbl, self) then
            wait_specs[i] = true
            keep_waiting = false
          end
        else
          local num_completed = 0
          for j, tbl in ipairs(wait_spec) do
            if tbl == true then
              num_completed = num_completed + 1
            else
              if not channel_is_sensitized(tbl, self) then
                wait_specs[i][j] = true
                num_completed = num_completed + 1
              end
            end
          end
          if num_completed == #wait_spec then
            wait_specs[i] = true
            keep_waiting = false
          end
        end
      end -- if wait_spec ~= true
    end -- for i, wait_spec in ipairs(wait_specs)
  end -- while keep_waiting

  ---@cast wait_specs (CTable|boolean|(CTable|boolean)[])[]

  for i, wait_spec in ipairs(wait_specs) do
    if wait_spec ~= true then
      if table_has_channel(wait_spec) then
        local tbl = wait_spec
        channel_desensitize(tbl, self)
        wait_specs[i] = false
      else
        for _, tbl in ipairs(wait_spec) do
          if tbl ~= true then
            channel_desensitize(tbl, self)
          end
        end
        wait_specs[i] = false
      end
    end
  end

  ---@cast wait_specs boolean[]

  return table_unpack(wait_specs)
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
---@return LogicalTime current_time
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
    -- TODO: test this
    error(err .. "\n" .. debug.traceback(p.cont))
  end
end

---- [[ Tick loop ]] ----

--- Iterator for scheduled processes; dequeues them from run queue and stack.
---
---@return fun(): (Process|nil)   iterator
---@return nil                    unused
---@return nil                    unused
local function scheduled_processes()
  return dequeue_next, nil, nil
end

--- Iterator for events scheduled at the current instant; dequeues them.
---
---@return fun(): Channel|nil   iterator
---@return LogicalTime          event_time
---@return nil                  unused
local function scheduled_events()
  return dequeue_event_at, M.next_event_time(), nil
end

--- Obtain number of active processes.
---
--- If this returns zero, SSM execution should terminate.
---
---@return integer active_processes
function M.num_active()
  return num_active
end

--- Time of the next scheduled update event, if any.
---
--- Returns NEVER if there is no event scheduled.
---
---@return LogicalTime next_update_time
function M.next_event_time()
  ---@type Channel|nil
  local c = event_queue:peek()
  if c == nil then
    return NEVER
  end
  return c.earliest
end

--- Get the current logical time.
---
---@return LogicalTime time
function M.current_time()
  return current_time
end

--- Advance time to a certain point in the future.
---
--- Time must strictly advance monotonically.
---
---@param next_time LogicalTime                   What time to advance to
---@return          LogicalTime   previous_time # The previous timestamp
function M.set_time(next_time)
  if current_time == NEVER and next_time == NEVER then
    return NEVER
  end

  dbg("===== ADVANCING TIME " .. tostring(current_time) .. " -> " .. tostring(next_time) .. " =====")

  assert(current_time < next_time, "Time must advance forwards " .. tostring(current_time) .. "-/->" .. tostring(next_time))

  local previous_time = current_time
  current_time = next_time
  return previous_time
end

--- Execute an instant. Performs all scheduled updates, then executes processes.
function M.run_instant()
  for c in scheduled_events() do
    channel_do_update(c)
  end

  for p in scheduled_processes() do
    process_resume(p)
  end
end

--- Spawn a root process that will execute on the first instant.
---
--- current_time is (re-)initialized to start_time, if start_time is specified;
--- otherwise, current_time is (re-)initialized to 0.
---
---@generic T
---@generic R
---
---@param entry_point fun(T...): R      The entry point function.
---@param entry_args  T[]|nil           Arguments given to entry_point.
---@param start_time  LogicalTime|nil   What to initialize current_time to
---@return            CTable            return_channel
function M.set_start(entry_point, entry_args, start_time)
  -- TODO: reset process tables etc.?
  current_time = start_time or 0
  local ret = M.make_channel_table({ terminated = false })
  push_process(process_new(entry_point, entry_args or {}, ret, Priority()))
  return ret
end

return M
