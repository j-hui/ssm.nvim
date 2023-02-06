-- stupid hack due to inconsistent package.path settings between distributions
package.path = './?/init.lua;./?.lua;' .. package.path

local ssm = require("ssm") { backend = "luv" }

function ssm.pause(d)
  local t = ssm.Channel {}
  t:after(ssm.msec(d), { [1] = 1 })
  ssm.wait(t)
end

function ssm.main()
  local stdin, stdout = ssm.io.get_stdin(), ssm.io.get_stdout()
  while true do
    ssm.wait(stdin)
    if not stdin.data then
      stdout.data = nil
      return
    end
    local str = stdin.data
    ssm.pause(250)
    stdout.data = tostring(ssm.as_msec(ssm.now())) .. ": " .. str
  end
end

print(ssm.start(ssm.main))
