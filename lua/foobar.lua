-- stupid hack due to inconsistent package.path settings between distributions
package.path = './?/init.lua;' .. package.path

local ssm = require("ssm") { backend = "luv" }

function ssm.foo(a)
  ssm.wait(a)                         -- Block on update to a
  a.val = a.val * 2                   -- Instant assignment
end

function ssm.bar(a)
  ssm.wait(a)                         -- Block on update to a
  a.val = a.val + 4                   -- Instant assignment
end

function ssm.main()
  local t = ssm.Channel { val = 0 }             -- Create channel table with { val = 0 }
  ssm.after(300, t).val = 1                       -- Delayed assignment of a.val = 1
  ssm.wait{ssm.bar:spawn(t), ssm.foo:spawn(t)}  -- fork/join on bar() and foo()
  return t.val, "main terminated at " .. tostring(ssm.now())
end

print(ssm.start(ssm.main))
