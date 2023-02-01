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
  self:wait{ssm:bar(t), ssm:foo(t)}   -- fork/join on bar() and foo()

  return t.val, "main terminated at " .. tostring(self:now())
end

print(ssm.start(ssm.main))
