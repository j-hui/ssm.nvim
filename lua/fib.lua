local ssm = require("ssm")

function ssm.pause(d)
  local t = ssm.Channel {}
  ssm.after(math.max(d, 1), t).val = 1
  ssm.wait(t)
end

function ssm.sum(r1, r2, d)
  ssm.wait { r1, r2 }
  ssm.pause(d)
  return r1[1] + r2[1]
end

function ssm.fib(n)
  if n < 2 then
    ssm.pause(n)
    return n
  end
  local r1 = ssm.fib:spawn(n - 1)
  local r2 = ssm.fib:spawn(n - 2)
  local r3 = ssm.sum:spawn(r1, r2, n)

  ssm.wait { r1, r2, r3 }

  return r3[1]
end

local n = 20
local t, v = ssm.start(function() return ssm.fib(n) end)

print("computed fib(" .. tostring(n) .. "): " .. tostring(v))
print("terminated at time: " .. tostring(t))
