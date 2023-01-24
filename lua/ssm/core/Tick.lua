local M = {}

local sched = require("ssm.core.sched")
local Process = require("ssm.core.Process")
local Time = require("ssm.core.Time")
local Channel = require("ssm.core.Channel")

local function doTick()
  for c in sched.ScheduledEvents() do
    Channel.Update(c)
  end

  for p in sched.ScheduledProcesses() do
    Process.Resume(p)
  end
end

function M.Start()
  doTick()
end

function M.Tick()
  local now = sched.AdvanceTime()

  if now == Time.NEVER then
    print("Time is never, not doing anything!")
    return false
  end

  doTick()
  return true
end

return M
