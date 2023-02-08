package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }
local uv = require("luv")

function ssm.pause(d)
  local t = ssm.Channel {}
  t:after(ssm.msec(d), { go = false })
  ssm.wait(t)
end

function ssm.fib(n)
  if n < 2 then
    ssm.pause(1)
    return n
  end
  local r1 = ssm.fib:spawn(n - 1)
  local r2 = ssm.fib:spawn(n - 2)
  ssm.wait { r1, r2, ssm.pause:spawn(n) }
  return r1[1] + r2[1]
end

local n = 10

ssm.start(function()
  local v = ssm.fib(n)

  print(("fib(%d) => %d"):format(n, v))
  --> fib(10) => 55

  local t = ssm.as_msec(ssm.now())
  print(("Completed in %.2fms"):format(t))
  --> Completed in 10.00ms
end)
