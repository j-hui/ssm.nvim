--- Internal implementation of the SSM library
local M = {}

local dbg = require("ssm.dbg")
local Priority = require("ssm.lib.Priority")
local PriorityQueue = require("ssm.lib.PriorityQueue")

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
local never = math.huge

-- Silly cast to satisfy sumneko...
---@cast never LogicalTime

--- Bottom element of logical timestamps.
---@type LogicalTime
M.never = never

--- Current logical time
---@type Time
local current_time = 0

----[[ Scheduler state and decision-making ]]----

--- Process table
---@type Process|nil
local current_proc = nil

--- Priority queue of processes to run.
-- @type PriorityQueue<Process>
local run_queue = PriorityQueue()

--- Priority queue for delayed update events to channel tables.
-- @type PriorityQueue<Channel>
local event_queue = PriorityQueue()

--- Number of active processes. When this hits zero, it's time to stop.
local num_active = 0

--- The highest and lowest priorities in the system.
---
--- @type Priority, Priority
local prio_highest, prio_lowest

--- Obtain process structure for currently running coroutine thread.
---
---@return  Process|nil     current_process
function M.get_current_process()
  return current_proc
end

--- Obtain process structure for currently running coroutine thread.
---
--- Unlike get_current_process(), this function will throw an error if nothing
--- is running.
---
---@return Process      current_process
local function get_running_process()
  local p = M.get_current_process()
  assert(p ~= nil, "Nothing is currently running")
  return p
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
  local p = run_queue:pop()

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

  if t == never or chan == nil or chan.earliest ~= t then
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

--- Get a new base priority; initialize prio_highest and prio_lowest.
---
---@return Priority base_priority
local function prio_init()
  prio_highest = Priority()
  local prio = prio_highest:insert()
  prio_lowest = prio:insert()
  return prio
end

--- Construct a priority higher than all existing priorities.
---
---@return Priority high_priority
local function make_high_priority()
  return prio_highest:insert()
end

--- Construct a priority lower than all existing priorities.
---
---@return Priority low_priority
local function make_low_priority()
  local prio = prio_lowest
  prio_lowest = prio:insert()
  return prio
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
--- Exported for compatibility with Lua versions that do not support __pairs().
---
---@generic K
---@generic V
---
---@param tbl table<K, V>   What to iterate over.
---@return fun(table: table<K, V>, i: integer|nil):K, V iterator
---@return table<K, V>                                  state
---@return nil                                          unused
function M.channel_pairs(tbl)
  local self = table_get_channel(tbl)
  local f = pairs(self.value)
  return f, tbl, nil
end

--- Override for channel tables' __ipairs() method.
---
--- Exported for compatibility with Lua versions that do not support __ipairs().
---
---@generic T
---
---@param tbl T[]           What to iterate over.
---@return fun(table: T[], i: integer|nil):integer, T   iterator
---@return T[]                                          state
---@return nil                                          unused
function M.channel_ipairs(tbl)
  local self = table_get_channel(tbl)
  local f = ipairs(self.value)
  return f, tbl, nil
end

--- Override for channel tables' __len() method.
---
--- Exported for compatibility with Lua versions that do not support __len().
---
---@param   tbl     CTable  The channel table
---@return          integer length
function M.channel_len(tbl)
  local self = table_get_channel(tbl)
  return #self.value
end

--- Construct a new Channel whose table is initialized with init.
---
---@param init    table     The table to initialize the channel's value with.
---@return        Channel   new_channel
local function channel_new(init)
  local chan = {
    later = {},
    last = {},
    earliest = never,
    triggers = {},
    __index = {},
    __newindex = channel_setter,
    __pairs = M.channel_pairs,
    __ipairs = M.channel_ipairs,
    __len = M.channel_len,
    name = "c" .. dbg.fresh(),
  }

  function chan.__tostring()
    return chan.name .. ".table"
  end

  local now = current_time

  chan.value = chan.__index

  for k, v in pairs(init) do
    chan.value[k], chan.last[k] = v, now
  end

  -- TODO: make this an empty piece of userdata?
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
  local next_earliest = never

  assert(self.earliest == current_time, "Not updating at the right time")
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

  -- Need to reschedule self for other queued updates
  if self.earliest ~= M.never then
    schedule_event(self)
  end
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
---@param tbl CTable      The channel table to schedule an update to.
---@param t   LogicalTime When to perform update.
---@param k   Key         The key to at which the delayed update is scheduled.
---@param v   any         The value to update k with.
function M.channel_schedule_update(tbl, t, k, v)
  local self = table_get_channel(tbl)
  assert(t > current_time, "Schedule time must be in the future")

  -- Updating the self.earliest field gets tricky if:
  -- - we're overwriting a scheduled update to a key, AND
  -- - we're changing it to a later update time, AND
  -- - the key we're overwriting was the earliest.
  if self.later[k] and self.later[k][1] < t and self.later[k][1] == self.earliest then
    self.later[k] = { t, v }
    -- We need to do a linear search for the earliest scheduled update time
    self.earliest = M.never
    for _, update in pairs(self.later) do
      self.earliest = math.min(self.earliest, update[1])
    end
  else
    -- Otherwise, we can safely fallback to the common case
    self.later[k] = { t, v }
    self.earliest = math.min(self.earliest, t)
  end

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

--- Resume execution of a process.
---@param p Process
local function process_resume(p)
  local prev = current_proc
  current_proc = p
  local ok, ret = coroutine.resume(p.cont)
  if ok then
    for i=#ret,1,-1 do
      -- Since run_after is maintained in reverse order, iterate backwards
      process_resume(ret[i])
    end
  else
    error(string.format("\n%s\nSSM %s:\n%s\n", ret, p.cont, debug.traceback(p.cont)))
  end
  current_proc = prev
end

---@class Process
---
--- Object to store metadata for running thread. Also the subject of self within
--- SSM routines; methods attached to Processes are part of SSM's public API.
---
---@field package cont      thread
---@field package prio      Priority
---@field private chan      Channel
---@field private name      string
---@field package active    boolean
---@field package scheduled boolean
---@field package run_after Process[]
local Process = {}
Process.__index = Process

function Process:__tostring()
  return self.name
end

--- Construct a new Process, without scheduling it for execution.
---
--- This function shouldn't be exposed to the user API, but it may be useful for
--- backends.
---
---@param func    fun(any): any   Function to execute in process.
---@param args    any[]           Table of arguments to routine.
---@param rtbl    CTable|nil      Return channel.
---@param prio    Priority        Priority of the process.
---@param active  boolean         Whether to create as an active process.
---@return        Process         new_process
local function process_new(func, args, rtbl, prio, active)
  local proc = {
    rtbl = rtbl,
    prio = prio,
    active = active,
    run_after = {},
    name = "p" .. dbg.fresh(),
  }

  -- proc becomes the self of func
  proc.cont = coroutine.create(function()
    local function pdbg(...)
      dbg("Process: " .. tostring(proc), ...)
    end

    pdbg("Created proc for function: " .. tostring(func),
      "return channel: " .. tostring(proc.rtbl))

    local r = { func(table_unpack(args)) }

    -- Set return values
    if proc.rtbl then
      for i, v in ipairs(r) do
        pdbg("Terminated.", "Assigning return value: [" .. tostring(i) .. "] " .. tostring(v))
        -- TODO: consider optimizing this using rawset()
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

    pdbg("Unregistered process")
    return proc.run_after
  end)

  setmetatable(proc, Process)

  if proc.active then
    num_active_inc()
  end

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
function M.process_spawn(func, ...)
  local cur = get_running_process()
  local args = { ... }

  local rtbl = M.make_channel_table({ terminated = false })

  -- Give the new process our current priority; give ourselves a new priority,
  -- immediately afterwards.
  local prio = cur.prio
  cur.prio = cur.prio:insert()

  process_resume(process_new(func, args, rtbl, prio, true))

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
function M.process_defer(func, ...)
  local cur = get_running_process()

  local args = { ... }
  local chan = M.make_channel_table({ terminated = false })
  local prio = cur.prio:insert()

  table.insert(cur.run_after, process_new(func, args, chan, prio, true))

  return chan
end

--- Create a process with either the highest priority or the lowest priority.
---
--- This should only be used to make I/Os for facilitating I/O.
---
---@generic T
---
---@param func      fun(T...)     The function the process should run.
---@param args      T[]           Arguments given to func.
---@param high_prio boolean|nil   Whether handler should be high priority.
function M.process_make_handler(func, args, high_prio)
  local prio = high_prio and make_high_priority() or make_low_priority()
  enqueue_process(process_new(func, args, nil, prio, false))
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
---@param   ... CTable|CTable[]   Wait specification
---@return      boolean ...       Whether that item unblocked
function M.process_wait(...)
  local cur = get_running_process()

  dbg(tostring(cur) .. ": waiting on " .. tostring(#{ ... }) .. " channels")

  ---@type (CTable|CTable[])[]
  local wait_specs = {}

  for i, wait_spec in ipairs { ... } do
    if table_has_channel(wait_spec) then
      local tbl = wait_spec
      dbg("Argument: " .. tostring(i) .. "->" .. tostring(tbl))

      wait_specs[i] = wait_spec
      channel_sensitize(tbl, cur)
    else
      wait_specs[i] = {}
      for j, tbl in ipairs(wait_spec) do
        dbg("Argument: " .. tostring(i) .. "." .. tostring(j) .. "->" .. tostring(tbl))

        wait_specs[i][j] = tbl
        channel_sensitize(tbl, cur)
      end
    end
  end

  if #wait_specs == 0 then
    return
  end

  ---@cast wait_specs (CTable|(CTable|true)[]|true)[]
  -- (true indicates the table at that position has been updated)

  local keep_waiting = true
  while keep_waiting do

    dbg(tostring(cur) .. ": about to yield due to wait")
    local run_after = cur.run_after
    cur.run_after = {}
    coroutine.yield(run_after)
    dbg(tostring(cur) .. ": returned from yield due to wait")

    -- At this point, all channel tables that this process is sensitive to have
    -- already removed this process from its sensitivity list (triggers).
    -- This process needs to iterate through and determine whether it is done
    -- waiting.

    for i, wait_spec in ipairs(wait_specs) do
      if wait_spec ~= true then
        if table_has_channel(wait_spec) then
          local tbl = wait_spec
          if not channel_is_sensitized(tbl, cur) then
            wait_specs[i] = true
            keep_waiting = false
          end
        else
          local num_completed = 0
          for j, tbl in ipairs(wait_spec) do
            if tbl == true then
              num_completed = num_completed + 1
            else
              if not channel_is_sensitized(tbl, cur) then
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

  ---@cast wait_specs (CTable|(CTable|true)[]|true|false)[]
  -- (false indicates the table at that position has not been updated)

  for i, wait_spec in ipairs(wait_specs) do
    if wait_spec ~= true then
      if table_has_channel(wait_spec) then
        local tbl = wait_spec
        channel_desensitize(tbl, cur)
        wait_specs[i] = false
      else
        for _, tbl in ipairs(wait_spec) do
          if tbl ~= true then
            channel_desensitize(tbl, cur)
          end
        end
        wait_specs[i] = false
      end
    end
  end

  ---@cast wait_specs boolean[]
  -- (at this point, everything should either be true or false)

  return table_unpack(wait_specs)
end

--- Mark the current running process as active; maintain process ref count.
function M.process_set_active()
  local self = get_running_process()
  if not self.active then
    num_active_inc()
    self.active = true
  end
end

--- Mark the current running process as passive; maintain process ref count.
function M.process_set_passive()
  local self = get_running_process()
  if self.active then
    num_active_dec()
    self.active = false
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
  return dequeue_event_at, current_time, nil
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
    return never
  end
  return c.earliest
end

--- Get the current logical time.
---
---@return LogicalTime time
function M.get_time()
  return current_time
end

--- Advance time to a certain point in the future.
---
--- Time must strictly advance monotonically.
---
---@param next_time LogicalTime                   What time to advance to
---@return          LogicalTime   previous_time # The previous timestamp
function M.set_time(next_time)
  if current_time == never and next_time == never then
    return never
  end

  dbg("===== ADVANCING TIME " .. tostring(current_time) .. " -> " .. tostring(next_time) .. " =====")

  assert(current_time < next_time,
    "Time must advance forwards " .. tostring(current_time) .. "-/->" .. tostring(next_time))

  local previous_time = current_time
  current_time = next_time
  return previous_time
end

--- Execute an instant. Performs all scheduled updates, then executes processes.
---
--- Nop if there is nothing scheduled for the current instant.
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
---@param entry_point fun(T...): R|nil  The entry point function.
---@param entry_args  T[]|nil           Arguments given to entry_point.
---@param start_time  LogicalTime|nil   What to initialize current_time to
---@return            CTable            return_channel
function M.set_start(entry_point, entry_args, start_time)
  -- TODO: reset process tables etc.?
  current_time = start_time or 0
  local ret = M.make_channel_table { terminated = false }
  enqueue_process(process_new(entry_point, entry_args or {}, ret, prio_init(), true))
  return ret
end

return M
