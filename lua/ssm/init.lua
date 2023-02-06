--- Public interface for the SSM library
local M = {}

local core = require("ssm.core")
local lua = require("ssm.lib.lua")

M.unpack = lua.unpack
M.pairs = lua.pairs
M.ipairs = lua.ipairs

---- [[ Time resolution ]] ----

--- The core library is resolution-agnostic, but for cross-platform accuracy we
--- will standardize to nanoseconds as our base resolution. Each backend will
--- need to adjust from nanoseconds accordingly.

---@param t number
---@return Duration t_nanoseconds
function M.nsec(t)
  ---@cast t Duration
  return t
end

---@param t number
---@return Duration t_microseconds
function M.usec(t)
  t = t * 1000
  ---@cast t Duration
  return t
end

---@param t number
---@return Duration t_milliseconds
function M.msec(t)
  t = t * 1000 * 1000
  ---@cast t Duration
  return t
end

---@param t number
---@return Duration t_seconds
function M.sec(t)
  t = t * 1000 * 1000 * 1000
  ---@cast t Duration
  return t
end

---@param d Duration|Timestamp
---@return number nanoseconds
function M.as_nsec(d)
  return d
end

---@param d Duration|Timestamp
---@return number microseconds
function M.as_usec(d)
  return d / 1000
end

---@param d Duration|Timestamp
---@return number milliseconds
function M.as_msec(d)
  return d / (1000 * 1000)
end

---@param d Duration|Timestamp
---@return number seconds
function M.as_sec(d)
  return d / (1000 * 1000 * 1000)
end

---- [[ Routines ]] ----

---@class Routine
---
---@field [1] fun(any): any
---
local Routine = {}
Routine.__index = Routine

--- Call the routine directory, from the same process.
function Routine:__call(...)
  return self[1](...)
end

--- Spawn a higher priority thread to run the routine.
function Routine:spawn(...)
  return core.process_spawn(self[1], ...)
end

--- Defer to a lower priority thread to run the routine.
function Routine:defer(...)
  return core.process_defer(self[1], ...)
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

---@generic T
---@type fun(fun: fun(T...), T...): table
M.spawn = core.process_spawn

---@generic T
---@type fun(fun: fun(T...), T...): table
M.defer = core.process_defer

---- [[ Channel methods ]] ----

function M.after(self, d, kvs)
  for k, v in M.pairs(kvs) do
    core.channel_schedule_update(self, core.get_time() + d, k, v)
  end
end

function M.get(self)
  return self[1]
end

function M.set(self, v)
  self[1] = v
end

--- Obtain the last time a channel table was updated.
---
---@type fun(tbl: table, key: any|nil): LogicalTime
M.last_updated = core.channel_last_updated

---- [[ Backend management ]] ----

local function set_backend(mod, backend_name)
  local backend = require("ssm.backend." .. backend_name)
  rawset(mod, "start", backend.start)
  rawset(mod, "io", backend.io)
  rawset(mod, "resolution", backend.resolution)
end

-- Default to simulation backend
set_backend(M, "simulation")

--- Start executing SSM from a specified entry point.
---
---@type fun(entry: fun(...): any, ...: any): LogicalTime, ...any
M.start = M.start -- nop (for documentation purposes)

---- [[ SSM user API ]] ----

--- Timestamp representing the end of time; larger than any other timestamp.
M.never = core.never

--- Obtain the current time.
M.now = core.get_time

--- Create a channel table from an initial value.
---
---@generic T table
---
---@param   init        T             Table to initialize channel table with.
---@param   no_clobber  boolean|nil   Set to falsy to prevent clobbering init.
---@return              T             new_channel_table
function M.Channel(init, no_clobber)
  if not no_clobber then
    init.after = M.after
    init.last_updated = M.last_updated
  end
  return core.make_channel_table(init)
end

--- Mark the current running process as active.
---@type fun(): nil
M.set_active = core.process_set_active

--- Mark the current running process as passive.
---@type fun(): nil
M.set_passive = core.process_set_passive

--- Wait for one or more channel tables to be updated.
---
---@type fun(...: table|table[]): boolean ...
M.wait = core.process_wait

--- Wait for all return channels to be updated, and unpack the results.
---
--- If multiple values are returned on an individual return channel, those
--- return values are packed into an array.
---
---@param tbls  table[]         Return channels
---@return      any|any[] ...   # Return values
function M.join(tbls)
  M.wait(tbls)
  for i, tbl in ipairs(tbls) do
    if core.channel_len(tbl) == 1 then
      tbls[i] = tbl[1]
    else
      tbls[i] = { M.unpack(tbl) }
    end
  end
  return M.unpack(tbls)
end

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

  if opts.backend then
    set_backend(mod, opts.backend)
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
