local ssm = require("ssm")

function ssm:pause(d)
  local t = ssm.Channel {}
  self:after(d, t, 1, 1)
  self:wait(t)
end

function ssm:sum(r1, r2)
  self:wait{r1, r2}
  self:wait(ssm:pause(1))
  return r1[1] + r2[1]
end

function ssm:fib(n)
  if n < 2 then
    self:wait(ssm:pause(1))
    return 1
  end
  local r1 = ssm:fib(n - 1)
  local r2 = ssm:fib(n - 2)
  local r3 = ssm:sum(r1, r2)

  self:wait{r1, r2, r3}

  return r3[1]
end

local t, v = ssm.start(function(self)
  local r = ssm:fib(10)
  self:wait(r)
  return r[1]
end)

print("terminated at time " .. tostring(t))
print("computed value " .. tostring(v))
