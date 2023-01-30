local ssm = require("ssm")

function ssm:foo(a)
  self:wait(a)                        -- Block on update to a
  a.val = a.val * 2                   -- Instant assignment
end

function ssm:bar(a)
  self:wait(a)                        -- Block on update to a
  a.val = a.val + 4                   -- Instant assignment
end

function ssm:main()
  ---@type table
  local t = ssm.Channel { val = 0 }   -- Create channel table with { val = 0 }
  self:after(3, t, "val", 1)          -- Delayed assignment of a.val = 1
  self:wait(ssm:bar(t), ssm:foo(t))   -- fork/join on bar() and foo()

  return t.val, self:now()
end

local time, ret1, ret2 = ssm.start(ssm.main)
print("time: " .. tostring(time))
print("return[1] (t.val): " .. tostring(ret1))
print("return[2] (self:now()): " .. tostring(ret2))
