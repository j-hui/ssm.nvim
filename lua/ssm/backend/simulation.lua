local M = {}

local core = require("ssm.core")
local lua = require("ssm.lib.lua")

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
  -- Execute first instant
  local ret = core.set_start(entry, { ... })
  core.run_instant()

  -- "Tick" loop
  while core.num_active() > 0 do
    local next_time = core.next_event_time()

    if next_time == M.never then
      return core.get_time(), lua.unpack(ret)
    end

    core.set_time(next_time)
    core.run_instant()
  end

  return core.get_time(), lua.unpack(ret)
end

return M
