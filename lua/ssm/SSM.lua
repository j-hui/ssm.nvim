local sched = require("ssm.core.sched")
local Process = require("ssm.core.Process")
local Tick = require("ssm.core.Tick")
local Channel = require("ssm.core.Channel")

local M = {}

M.Start = Tick.Start
M.Tick = Tick.Tick
M.Channel = Channel.New

local meta = {
  __newindex = function(t, k, v)
    rawset(t, k, function(_, ...)
      local cur = sched.getCurrent()
      if cur then
        return cur:call(v, ...)
      else
        Process.Start(v, { ... })
      end
    end)
  end
}

return setmetatable(M, meta)
