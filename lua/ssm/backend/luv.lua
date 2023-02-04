--[[  Event loop order:

    - Update loop time
    -----> End if loop is stopped

    - Run due timers

    - (Pending I/O callbacks; this doesn't really happen)

    - Run idle handles

    - Run prepare handles
        + we will set time here (?)
        + we will tick here

    |===== Poll for I/O AKA block =====|

    - I/O callbacks
        + for inputs, we can safely schedule delayed updates to
          corresponding channels

    - Run check handles

    - Call close callbacks
  ]]

local M = {}

local core = require("ssm.core")
local lua = require("ssm.lib.lua")

local uv
-- For some silly reason, luv is called "uv" inside of the luvit environment
if not pcall(function() uv = require("luv") end) then
  uv = require("uv")
end

function M.wrap_input_stream(stream)
  local chan = core.make_channel_table { data = "", err = nil, stream = stream }
  stream:read_start(function(err, data)
    local now = uv.hrtime()
    if err then
      core.channel_schedule_update(chan, now, "err", err)
      core.channel_schedule_update(chan, now, "data", nil)
      stream:close()
    elseif data then
      core.channel_schedule_update(chan, now, "data", data)
    else
      core.channel_schedule_update(chan, now, "data", nil)
      stream:close()
    end
  end)
  return chan
end

local function output_handler(stream, chan)
  core.process_set_passive()
  local should_continue = true

  while should_continue do
    core.process_wait(chan)

    if not should_continue or chan.data == nil then
      stream:close()
      return
    end

    stream:write(chan.data, function(err)
      if err then
        stream:close()
        chan.data = nil
        should_continue = false
      end
    end)
  end
end

function M.wrap_output_stream(stream)
  local chan = core.make_channel_table { data = "", err = nil, stream = stream }
  core.process_defer(output_handler, stream, chan)
  return chan
end

local function setup_stdio()
  -- Setup stdin
  local stdin
  if uv.guess_handle(0) == "tty" then
    stdin = uv.new_tty(0, true)
  else
    stdin = uv.new_pipe()
    stdin:open(0)
  end

  M.io.stdin = M.wrap_input_stream(stdin)

  local stdout
  if uv.guess_handle(1) == "tty" then
    stdout = uv.new_tty(1, false)
  else
    stdout = uv.new_pipe()
    stdout:open(1)
  end

  M.io.stdout = M.wrap_output_stream(stdout)
end

local function shutdown_stdio()
    if not M.io.stdin.stream:is_closing() then
      M.io.stdin.stream:close()
    end
    if not M.io.stdout.stream:is_closing() then
      M.io.stdout.stream:close()
    end
end

local timer, ticker

local function refresh_timer()
  if core.next_event_time() == core.never then
    return
  end

  local sleep_time = math.max(core.next_event_time() - uv.hrtime())
  -- Unfortunately, luv's timers only support millisecond resolution...
  timer:start(sleep_time / 1000000, 0, function() end)
end

local function do_tick()
  core.run_instant()

  if core.num_active() <= 0 then
    shutdown_stdio()
    ticker:stop()
  else
    refresh_timer()
  end
end


--- Start executing SSM from a specified entry point.
---
---@generic T
---@generic R
---
---@param entry         fun(T...): R        Entry point for SSM execution
---@param ...           T                   Arguments applied to entry point
---@return LogicalTime  completion_time     # When SSM execution completed
---@return R            return_value        # Return value of the entry point
M.start = function(entry, ...)
  -- Save varargs so that they can be used within an anonymous function.
  local args = { ... }

  -- We will eventually return this at the end of start().
  local ret

  -- One-shot timer to implement real-time behavior.
  --
  -- We will use this timer handle as a one-shot timer, i.e., always calling
  -- timer:start() with the second argument (repeat) set to 0.
  timer = uv.new_timer()

  -- Instants will run in libuv's prepare phase.
  ticker = uv.new_prepare()

  -- This first invocation will execute as soon as we execute uv.run(), and
  -- initialize
  timer:start(0, 0, function()
    -- For first iteration only, initialize model time to that of uv
    ret = core.set_start(function()
      setup_stdio()

      local entry_ret = { entry(args) }

      return unpack(entry_ret)
    end, nil, uv.hrtime())

    -- A little bit of callback hell to make sure the first instant runs during
    -- the prepare phase.
    ticker:start(function()
      do_tick()

      ticker:start(function()
        if uv.hrtime() < core.next_event_time() then
          -- Spurious wake up, but we are not yet ready to tick.
          refresh_timer()
          return
        end
        core.set_time(core.next_event_time())
        do_tick()
      end)
    end)
  end)

  -- Runs in "default" mode, which blocks until the event loop stops.
  --
  -- In our implementation, the event loop will stop when there are no more
  -- active handles; we won't explicitly call uv.stop().
  uv.run()

  return core.get_time(), lua.unpack(ret)
end

-- For I/O, we want a function that will transform a stream_handle_t to
-- a channel table.  Exactly what happens with that channel table depends on
-- whether it used for reading, writing, or high priority writing.

M.io = {}
-- M.io.stdin
-- M.io.stdout
-- M.io.stderr

return M
