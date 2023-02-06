package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }

function ssm.pause(d)
  local t = ssm.Channel {}
  t:after(ssm.msec(math.max(d, 1)), { [1] = 1 })
  ssm.wait(t)
end

function ssm.sum(r1, r2, d)
  local v1, v2 = ssm.join { r1, r2 }
  ssm.pause(d)
  return v1 + v2
end

function ssm.fib(n)
  if n < 2 then
    ssm.pause(n)
    return n
  end
  local r1, r2 = ssm.fib:spawn(n - 1), ssm.fib:spawn(n - 2)
  local result = ssm.sum:spawn(r1, r2, n)
  ssm.wait { r1, r2, result }
  return result[1]
end

local n = 20
local t, v = ssm.start(ssm.fib, n)

print("computed fib(" .. tostring(n) .. "): " .. tostring(v))
print("terminated at time: " .. tostring(ssm.as_msec(t)))
