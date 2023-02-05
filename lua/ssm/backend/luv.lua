--[[  Event loop order:

    - Update loop time
    -----> End if loop is stopped

    - Run due timers

    - (Pending I/O callbacks; this doesn't really happen)

    - Run idle handles

    - Run prepare handles

    |===== Poll for I/O AKA block =====|

    - I/O callbacks
        + for inputs, we can safely schedule delayed updates to
          corresponding channels

    - Run check handles

    - Call close callbacks
  ]]

local M = {}
M.io = {}

local core = require("ssm.core")
local lua = require("ssm.lib.lua")

local uv
-- For some silly reason, luv is called "uv" inside of the luvit environment
if not pcall(function() uv = require("luv") end) then
  uv = require("uv")
end

local timer, try_tick, start_time

local function set_wallclock()
  start_time = uv.hrtime()
end

local function get_wallclock()
  return uv.hrtime() - start_time
end

local function refresh_timer()
  if core.next_event_time() == core.never then
    return
  end

  local sleep_time = math.max(core.next_event_time() - get_wallclock())
  -- Unfortunately, luv's timers only support millisecond resolution...
  sleep_time = sleep_time / 1000000
  sleep_time = math.max(sleep_time, 0)
  timer:start(sleep_time, 0, try_tick)
end

local function do_tick()
  core.run_instant()
  if core.num_active() <= 0 then
    -- How to close low priority stuff?
  else
    refresh_timer()
  end
end

function try_tick()
  if get_wallclock() < core.next_event_time() then
    -- Spurious wake up, but we are not yet ready to tick.
    refresh_timer()
    return
  end
  core.set_time(core.next_event_time())
  do_tick()
end

local function input_handler(chan)
  core.process_set_passive() -- Should be redundant
  while true do
    core.process_wait(chan)
    if not chan.data then
      if not chan.stream:is_closing() then
        chan.stream:close()
      end
      return
    end
  end
end

local function output_handler(stream, chan)
  core.process_set_passive() -- Should be redundant
  local should_continue = true

  while should_continue do
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

    core.process_wait(chan)
  end
end

function M.io.wrap_input_stream(stream)
  ---@type table
  local chan = core.make_channel_table {
    data = "",
    err = nil,
    stream = stream
  }

  local function input_callback(err, data)
    local now = get_wallclock()
    ---@cast now LogicalTime
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
    core.set_time(now)
    do_tick()
  end

  stream:read_start(input_callback)
  core.process_make_handler(input_handler, { chan }, false)

  return chan
end

function M.io.wrap_output_stream(stream)
  local chan = core.make_channel_table { data = "", err = nil, stream = stream }
  core.process_make_handler(output_handler, { stream, chan }, false)
  return chan
end

function M.open_stream_fd(fd, read, fd_type)
  local stream_type = uv.guess_handle(fd)
  if fd_type and stream_type ~= fd_type then
    return nil
  end

  local stream
  if stream_type == "tty" then
    stream = uv.new_tty(fd, read)
  elseif stream_type == "pipe" then
    stream = uv.new_pipe()
    stream:open(fd)
  else
    return nil
  end

  if read then
    return M.io.wrap_input_stream(stream)
  else
    return M.io.wrap_output_stream(stream)
  end
end

local stdin_chan
function M.io.get_stdin(tty_type)
  if not stdin_chan then
    stdin_chan = M.open_stream_fd(0, true, tty_type)
  end
  return stdin_chan
end

local stdout_chan
function M.io.get_stdout(tty_type)
  if not stdout_chan then
    stdout_chan = M.open_stream_fd(1, false, tty_type)
  end
  return stdout_chan
end

local stderr_chan
function M.io.get_stderr(tty_type)
  if not stderr_chan then
    stderr_chan = M.open_stream_fd(2, false, tty_type)
  end
  return stderr_chan
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

  -- This first invocation will execute as soon as we execute uv.run(), and
  -- initialize
  timer:start(0, 0, function()
    set_wallclock()
    -- Note that we initialize model time to 0
    ret = core.set_start(entry, args, 0)
    do_tick()
  end)

  -- Runs in "default" mode, which blocks until the event loop stops.
  --
  -- In our implementation, the event loop will stop when there are no more
  -- active handles; we won't explicitly call uv.stop().
  uv.run()

  return core.get_time(), lua.unpack(ret)
end

return M
