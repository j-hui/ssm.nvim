---@diagnostic disable: deprecated
unpack = table.unpack

local SSM = require("ssm.SSM")

function SSM:foo(a) -- Note: a points to the table created in main()

  print("foo: wait at time " .. self:now())
  self:wait(a)                        -- Block on update to a
  print("foo: unblocked at time " .. self:now())

  a.val = a.val * 2                   -- Instant assignment
end

function SSM:bar(a) -- Note: a points to the table created in main()

  print("bar: wait at time " .. self:now())
  self:wait(a)                        -- Block on update to a
  print("bar: unblocked at time " .. self:now())

  a.val = a.val + 4                   -- Instant assignment
end

function SSM:main()
  ---@type table
  local t = SSM.Channel { val = 0 }   -- Create channel table with { val = 0 }

  self:after(4, t, "val", 1)          -- Delayed assignment of a.val = 1

  self:wait(SSM:bar(t), SSM:foo(t))   -- fork/join on bar() and foo()

  print("main: value is " .. tostring(t.val) .. " at time " .. self:now())
end


--- Ignore this stuff...
SSM:main() SSM.Start() SSM.Tick()
