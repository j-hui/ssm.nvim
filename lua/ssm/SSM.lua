local M = {}

local sched = require("ssm.core.sched")

local meta = {}

function meta.__newindex(t, k, v)
  rawset(t, k, function(...)
    sched.getCurrent():call(v, ...)
  end)
end

return setmetatable(M, meta)
