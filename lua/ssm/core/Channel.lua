local M = {}

local sched = require("ssm.core.sched")
local Time = require("ssm.core.Time")

---@class CTable: table
---@alias Key any
---@alias IsSched true|table<Key, true>
---@alias Event {[1]: Time, [2]: any}

---@class Channel
---
---@field package table     CTable              Table attached
---@field package value     table<Key, any>     Current value
---@field package last      table<Key, Time>    Last modified time
---@field package later     table<Key, Event>   Delayed update events
---@field package earliest  Time                Earliest scheduled update
---@field package triggers  table<Process, IsSched>   What to run when updated
local Channel = {}
Channel.__index = Channel

M.Channel = Channel

--- Obtain the Channel metatable of a channel table.
---
---@param tbl CTable
---@return    Channel
local function getChannel(tbl)
  return getmetatable(tbl)
end

--- See if a table has a channel attached ot it.
---
---@param o   table     The table to check.
---@return    boolean   Whether o has a channel attached.
function M.hasChannel(o)
  return getmetatable(getChannel(o)) == Channel
end

--- Construct a new Channel whose table is initialized with init.
---
---@param init    table     The table to initialize the channel's value with.
---@return        Channel   The newly constructed Channel.
function Channel.new(init)
  local chan = {
    value = {},
    later = {},
    last = {},
    earliest = Time.NEVER,
    triggers = {},
    __index = M.get,
    __newindex = M.set,
  }

  local now = sched.logicalTime()

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

--- Obtain the table a channel is attached it.
---
---@param self  Channel
---@return      CTable
function M.getTable(self)
  return self.table
end

--- Obtain the earliest time a channel table is scheduled for an update.
---
---@param self  Channel
---@return      Time
function M.nextUpdateTime(self)
  return self.earliest
end

--- Perform delayed update on a channel table, and schedule sensitive processes.
---
---@param self Channel
function M.update(self)
  local nextEarliest = Time.NEVER

  assert(self.earliest == sched.logicalTime(), "Updating at the right time")
  local updated_keys = {}

  for k, e in pairs(self.later) do
    local t, v = e[1], e[2]

    if t == self.earliest then
      self.value[k], self.last[k] = v, t
      self.later[k] = nil
      table.insert(updated_keys, k)
    else
      assert(Time.lt(self.earliest, t), "Updates are taking place out of order??")
      nextEarliest = Time.min(nextEarliest, t)
    end
  end

  self.earliest = nextEarliest

  -- Accumulator for processes not triggered
  local remaining = {}

  for p, e in pairs(self.triggers) do

    if e == true then
      sched.enqueueProcess(p)
      e = nil
    else
      for _, k in ipairs(updated_keys) do
        if e[k] == true then
          sched.enqueueProcess(p)
          e = nil
          break
        end
      end
    end

    remaining[p] = e
  end

  self.triggers = remaining
end

--- Construct a new table with an attached channel.
---
---@param init  table   The table to initialize the channel's value with.
---@return      CTable  The newly constructed channel table.
function M.new(init)
  return Channel.new(init).table
end

--- Getter for channel tables.
---
---@param tbl CTable
---@param k   Key
---@return    any
function M.get(tbl, k)
  return getChannel(tbl).value[k]
end

--- Setter for channel tables; schedules sensitive lower priority processes.
---
--- If v is nil (i.e., the caller is deleting the field k), the corresponding
--- last field is also deleted.
---
---@param tbl CTable
---@param k   Key
---@param v   any
function M.set(tbl, k, v)
  local self = getChannel(tbl)

  local t = v == nil and nil or sched.logicalTime()
  self.value[k], self.last[k] = v, t

  local cur = sched.getCurrent()

  -- Accumulator for processes not triggered
  local remaining = {}

  for p, e in pairs(self.triggers) do
    if cur < p and (e == true or e[k] == true) then
      -- Enqueue any lower priority process that is sensitized to:
      -- (1) any update to table or (2) updates to table[k]
      sched.enqueueProcess(p)
    else
      -- Processes not enqueued for execution remain sensitive.
      remaining[p] = e
    end
  end

  self.triggers = remaining
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
function M.last(tbl, k)
  local self = getChannel(tbl)

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

--- Sensitize a process to updates on a channel table.
---
--- If k is nil, p is sensitized to any updates to tbl. If p was already
--- sensitized to updates to some keys of p, those get overruled by
--- sensitization to any update to tbl.
---
--- If p was already sensitized to any updates to tbl, this method does nothing.
---
---@param tbl CTable    The channel table to be sensitized to.
---@param p   Process   The process to sensitize.
---@param k   Key|nil   The key to whose updates p should be sensitive to.
function M.sensitize(tbl, p, k)
  local self = getChannel(tbl)

  if k == nil then
    -- p is notified for any update to self.table

    -- Even if there was already an entry, we can just overwite it with
    -- a catch-all entry.
    self.triggers[p] = true
  else
    -- p is notified for updates to tbl[k]

    if self.triggers[p] then
      -- There is already a triggers entry for p; update it.

      if self.triggers[p] ~= true then
        -- p is only sensitized on updates to certain keys of tbl;
        -- add sub-entry for k.
        self.triggers[p][k] = true
      end
    else
      -- p is not yet sensitized for updates to tbl; create triggers entry.
      self.triggers[p] = { k = true }
    end
  end
end

--- Remove the trigger for a process, desensitizing it from updates to tbl.
---@param tbl CTable    The channel table to be desensitized from.
---@param p   Process   The process to desensitize.
function M.desensitize(tbl, p)
  local self = getChannel(tbl)
  self.triggers[p] = nil
end

--- Scheduld a delayed update to a channel table.
---
---@param tbl CTable    The channel table to schedule an update to.
---@param d   Duration  How far in the future to schedule an update for.
---@param k   Key       The key to at which the delayed update is scheduled.
---@param v   any       The value to update k with.
function M.after(tbl, d, k, v)
  local self = getChannel(tbl)

  local t = sched.logicalTime() + d

  self.later[k] = { t, v }
  self.earliest = Time.min(self.earliest, t)

  sched.scheduleEvent(self)
end

return M
