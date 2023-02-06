package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }

function ssm.pause(d)
  local t = ssm.Channel {}
  t:after(ssm.msec(d), { [1] = 1 })
  ssm.wait(t)
end

function ssm.sum(r1, r2, d)
  ssm.wait { r1, r2 }
  ssm.pause(d)
  return r1[1] + r2[1]
end

function ssm.fib(n)
  if n < 2 then
    ssm.pause(1)
    return n
  end
  local r1 = ssm.fib:spawn(n - 1)
  local r2 = ssm.fib:spawn(n - 2)
  local result = ssm.sum:spawn(r1, r2, n)
  ssm.wait { r1, r2, result }
  return result[1]
end

local n = 20
local t, v = ssm.start(ssm.fib, n)

print(("fib(%d) => %d"):format(n, v))
t = ssm.as_msec(t)
print(("Completed in %.2fms"):format(t))
