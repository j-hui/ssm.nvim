--- Public interface for the SSM library
local M = {}

local internal = require("ssm.internal")

--- Forwards-compatible implementation of unpack that uses overloaded __index.
---
--- The builtin unpack() doesn't work with tables whose __index is overloaded.
---
---@param t table
---@param i number|nil
---@return any ...
function M.unpack(t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], M.unpack(t, i + 1)
  end
end

local rawpairs = pairs

--- Fowards-compatible implementation of pairs that uses overloaded __pairs.
---
---@generic K
---@generic V
---
---@param t table<K,V>                              table
---@return fun(table: table<K, V>, i: integer): V   iterator
---@return table<K, V>                              state
---@return nil                                      index
function M.pairs(t)
  local m = getmetatable(t)
  local p = m and m.__pairs or rawpairs
  return p(t)
end

local rawipairs = ipairs

--- Fowards-compatible implementation of pairs that uses overloaded __ipairs.
---
---@generic T
---
---@param t T[]                                   array
---@return fun(table: T[], i: integer): integer   iterator
---@return T[]                                    state
---@return integer                                index
function M.ipairs(t)
  local m = getmetatable(t)
  local p = m and m.__ipairs or rawipairs
  return p(t)
end

---- [[ Routines ]] ----

---@class Routine
local Routine = {}
Routine.__index = Routine

function Routine:__call(...)
  return self[1](...)
end

function Routine:spawn(...)
  return internal.process_spawn(self[1], ...)
end

function Routine:defer(...)
  return internal.process_defer(self[1], ...)
end

--- Create an SSM routine that can be called, spawned, or deferred.
---
--- ssm_define() is used to override the __newindex() method of this SSM module.
--- It works like this:
---
--- 1.  The user writes
---
---         function ssm:<name>(<args>) <body> end
---
---     which gets desugared to
---
---         ssm.<name> = function(<args>) <body> end
---
---     (The user may also directly write the desugared version.)
---
--- 2.  The new index assignment dispatches a call to the overridden
---     __newindex() method (i.e., ssm_define()).
---
---         getmetatable(ssm).__newindex(ssm, "<name>",
---                                      function(<args>) <body> end)
---
--- 3.  The __new_index() is ssm_define(), so we enter ssm_define() with
---     tbl = ssm, key = "<name>", and method = function(<args>) <body> end.
---
--- 4.  ssm_define() wraps method in a function f that, when invoked within an
---     SSM execution, dispatches the a :call() of the method from the running
---     process context.
---
--- 5.  ssm_define() uses rawset() to assign that wrapper function f to
---     tbl["<name>"], i.e., ssm.<name>.
---
--- This way, an SSM process can call other SSM functions like:
---
---     ssm:func(args)
---
--- instead of:
---
---     self:call(ssm.func, args)
---
---
---@param f fun(any): any
---@return  Routine         new_routine
local function routine_create(f)
  return setmetatable({ f }, Routine)
end

---- [[ Channel Lenses ]] ----

---@class Lens
---
---@field [1] table
---@field [2] Duration
local Lens = {}
Lens.__index = Lens

-- Lenses seem rife for misuse; lock down the metatable to prevent mischief.
Lens.__getmetatable = false

--- Schedule a delayed update to a key of the enclosed channel table.
---
---@param lens  Lens
---@param k     any
---@param v     any
function Lens.__newindex(lens, k, v)
  local tbl, d = lens[1], lens[2]
  internal.channel_schedule_update(tbl, d, k, v)
end

--- Create an assignable object that schedule updates on tbl after d.
---
---@param d   Duration    How long after current time to assign to tbl.
---@param tbl table       The channel table to assign to.
---@return    Lens        assignable_table
local function lens_create(d, tbl)
  return setmetatable({ tbl, d }, Lens)
end

---- [[ SSM user API ]] ----

--- Start executing SSM from a specified entry point.
---
--- The entry point may either be an SSM routine, SSM.fn, previously defined
--- using function ssm:fn() ... end, or an anonymous function, i.e.,
--- function(self) ... end.
---
---@generic T
---
---@param entry_point  function           Entry point for SSM execution
---@return LogicalTime completion_time    # When SSM execution completed.
---@return T           return_value       # Return value of the entry point.
M.start = function(entry_point)
  -- Execute first instant
  local ret = internal.set_start(entry_point)
  internal.run_instant()

  -- "Tick" loop
  while internal.num_active() > 0 do
    local next_time = internal.next_event_time()

    if next_time == M.never then
      return internal.get_time(), M.unpack(ret)
    end

    internal.set_time(next_time)
    internal.run_instant()
  end

  return internal.get_time(), M.unpack(ret)
end

--- Timestamp representing the end of time; larger than any other timestamp.
---
---@type LogicalTime
M.never = internal.never

--- Obtain the current time.
---
---@type fun(): LogicalTime
M.now = internal.get_time

--- Create a channel table from an initial value.
---
---@type fun(init: table): table
M.Channel = internal.make_channel_table

--- Create a lens object that can be assigned to schedule delayed assignments.
---
---@type fun(delay: Duration, tbl: table): Lens
M.after = lens_create

--- Obtain the last time a channel table was updated.
---
---@type fun(tbl: table, key: any|nil): LogicalTime
M.last_updated = internal.channel_last_updated

--- Wait for one or more channel tables to be updated.
---
---@type fun(...: table|table[]): boolean ...
M.wait = internal.process_wait

--- TODO: document
---@type fun(): nil
M.set_active = internal.process_set_active

--- TODO: document
---@type fun(): nil
M.set_passive = internal.process_set_passive

--- Configure the SSM runtime library.
---
--- Overrides the __call() method of the SSM public module, so a user can
--- configure it like this:
---
---   local ssm = require("ssm") { option_name = option_value }
---
--- Available options (with defaults):
---
---   {
---     override_pairs = false,   -- Redefine builtin pairs() and ipairs()
---   }
---
--- For now, the behavior of calling this function multiple times is undefined.
---
---@param mod any
---@param opts any
---@return any
local function configure(mod, opts)
  opts = opts or {}
  if opts.override_pairs then
    pairs = M.pairs
    ipairs = M.ipairs
  end
  return mod
end

return setmetatable(M, {
  __newindex = function(tbl, k, f)
    if type(f) == "function" then
      rawset(tbl, k, routine_create(f))
    else
      rawset(tbl, k, f)
    end
  end,
  __call = configure,
})
