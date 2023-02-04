-- stupid hack due to inconsistent package.path settings between distributions
package.path = './?/init.lua;' .. package.path

local ssm = require("ssm") { backend = "luv" }

function ssm.main()
  while true do
    ssm.wait(ssm.io.stdin)
    if not ssm.io.stdin.data then
      return
    end
    ssm.io.stdout.data = tostring(ssm.now()) .. ": " .. ssm.io.stdin.data
  end
end

print(ssm.start(ssm.main))
