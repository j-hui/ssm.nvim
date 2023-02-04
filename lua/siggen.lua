package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm")

function ssm.sig_gen(half_period)
  ssm.set_passive()
  while true do

  end
end

function ssm.sig_ctl(button1, button2, half_period)
  while true do
    ssm.wait(button1, button2)
    if ssm.last_updated(button1) == ssm.now() then
      half_period.val = half_period.val * 2
    else
      half_period.val = half_period.val / 2
    end
  end
end

function ssm.main()
  local half_period = ssm.Channel { val = 1000 }
  local button1, button2

  ssm.sig_gen:spawn(half_period)
  ssm.sig_ctl:spawn(button1, button2, half_period)
end
