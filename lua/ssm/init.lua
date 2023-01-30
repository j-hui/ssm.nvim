--- Public interface for the SSM library
local M = {}

local internal = require("ssm.internal")

function M.unpack(t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], M.unpack(t, i + 1)
  end
end

local rawpairs = pairs
function M.pairs(t)
  local m = getmetatable(t)
  local p = m and m.__pairs or rawpairs
  return p(t)
end

local rawipairs = ipairs
function M.ipairs(t)
  local m = getmetatable(t)
  local p = m and m.__ipairs or rawipairs
  return p(t)
end

---@type fun(init: table): table
M.Channel = internal.make_channel_table

---@type fun(tbl: table, key: any|nil): LogicalTime
M.last_updated = internal.channel_last_updated

M.Time = internal.Time

M.NEVER = internal.Time.NEVER

---@type table<function, function>
local methods = {}

M.start = function(f)
  local ret
  if methods[f] then
    ret = internal.spawn_root_process(methods[f])
  else
    ret = internal.spawn_root_process(f)
  end

  internal.run_instant()

  while internal.num_active() > 0 do
    local next_time = internal.next_update_time()

    if next_time == internal.Time.NEVER then
      return internal.current_time(), M.unpack(ret)
    end

    internal.set_time(next_time)
    internal.run_instant()
  end

  return internal.current_time(), M.unpack(ret)
end

local function ssm_define(tbl, key, method)
  local function f(_, ...)
    return internal.get_current_process():call(method, ...)
  end

  methods[f] = method
  rawset(tbl, key, f)
end

local function ssm_configure(mod, opts)
  opts = opts or {}
  if opts.override_pairs then
    pairs = M.pairs
    ipairs = M.ipairs
  end
  return mod
end

return setmetatable(M, {
  __newindex = ssm_define,
  __call = ssm_configure,
})
