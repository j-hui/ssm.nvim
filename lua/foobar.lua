-- stupid hack due to inconsistent package.path settings between distributions
package.path = './?/init.lua;./?.lua;' .. package.path

local ssm = require("ssm") { backend = "luv" }

function ssm.foo(a)
  ssm.wait(a) -- Block on update to a
  a.val = a.val * 2 -- Instant assignment
end

function ssm.bar(a)
  ssm.wait(a) -- Block on update to a
  a.val = a.val + 4 -- Instant assignment
end

function ssm.main()
  local start_time = ssm.now()
  local t = ssm.Channel { val = 0 } -- Create channel table with { val = 0 }
  ssm.after(ssm.msec(300), t).val = 1 -- Delayed assignment of a.val = 1
  ssm.wait { ssm.bar:spawn(t), ssm.foo:spawn(t) } -- fork/join on bar() and foo()

  local end_time = ssm.now()
  return t.val, "main terminated after " .. tostring(ssm.as_msec(end_time - start_time)) .. "ms"
end

print(ssm.start(ssm.main))
