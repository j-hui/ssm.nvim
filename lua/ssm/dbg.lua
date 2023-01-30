local M = {}

setmetatable(M, {
  __call = function(_, ...)
    return
    -- local info = debug.getinfo(2)
    -- local loc = string.format("%s:%d", info.short_src, info.currentline)
    --
    -- print("--- " .. loc .. " ---")
    -- print()
    -- for _, msg in ipairs { ... } do
    --   print("    " .. msg)
    -- end
    -- print()
    --
    -- print(debug.traceback())
    -- print("--------")
    -- print()
    -- print()
  end
})

local ctr = 0

function M.fresh()
  ctr = ctr + 1
  return ctr
end

return M
