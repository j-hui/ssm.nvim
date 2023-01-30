--- Public interface for the SSM library
local M = {}

local internal = require("ssm.internal")

M.Channel = internal.make_channel_table
M.last_updated = internal.channel_last_updated
M.Time = internal.Time
M.NEVER = internal.Time.NEVER

---@type table<function, function>
local methods = {}

M.start = function(f)
  if methods[f] then
    M.start(methods[f])
  else
    M.start(f)
  end
end

return setmetatable(M, {
  __newindex = function(tbl, key, method)
    local function f(_, ...)
      return internal.get_current_process():call(method, ...)
    end
    methods[f] = method
    rawset(tbl, key, f)
  end
})
