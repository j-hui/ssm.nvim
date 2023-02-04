-- stupid hack due to inconsistent package.path settings between distributions
package.path = './?/init.lua;./?.lua;' .. package.path

local ssm = require("ssm") { backend = "luv" }

function ssm.main()
  local start = ssm.now()
  while true do
    ssm.wait(ssm.io.stdin)
    if not ssm.io.stdin.data then
      return
    end
    print(ssm.io.stdin.data)
    ssm.io.stdout.data = tostring(ssm.as_msec(ssm.now() - start)) .. ": " .. ssm.io.stdin.data
  end
end

print(ssm.start(ssm.main))
