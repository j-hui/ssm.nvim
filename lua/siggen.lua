package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }

function ssm.sig_gen(ctl, out)
  ssm.set_passive()
  while true do
    out:after(ctl.period / 2, { output = not out.output })
    ssm.wait(out)
  end
end

function ssm.sig_ctl(up, down, ctl)
  ssm.set_passive()
  while true do
    local did_up, did_down = ssm.wait(up, down)
    if did_up and not did_down then
      -- Halve the period to increase the frequency
      ctl.period = ctl.period / 2
    elseif did_down and not did_up then
      -- Double the period to decrease the frequency
      ctl.period = ctl.period * 2
    end
  end
end

function ssm.main(up, down, out)
  local ctl = ssm.Channel { period = ssm.msec(1000) }
  ssm.sig_gen:spawn(ctl, out)
  ssm.sig_ctl:spawn(up, down, ctl)
end

function ssm.stdin_handler(up, down)
  local stdin = ssm.io.get_stdin()
  stdin.stream:set_mode(1)
  local up_key, down_key, quit_key = string.byte("k"), string.byte("j"), string.byte("q")
  while true do
    ssm.wait(stdin)
    if not stdin.data or stdin.data:byte(1) == quit_key then
      break
    end
    if stdin.data:byte(1) == up_key then
      up[1] = true
    elseif stdin.data:byte(1) == down_key then
      down[1] = true
    end
  end
  require("luv").tty_reset_mode()
end

function ssm.stdout_handler(out)
  ssm.set_passive()
  local stdout = ssm.io.get_stdout()
  while true do
    ssm.wait(out)
    if out.output == nil then
      break
    end
    if out.output then
      stdout.data = "1"
    else
      stdout.data = "0"
    end
  end
  stdout.data = nil
end

function ssm.entry()
  local up, down, out = ssm.Channel {}, ssm.Channel {}, ssm.Channel {}
  ssm.stdin_handler:spawn(up, down)
  ssm.stdout_handler:defer(out)
  ssm.main(up, down, out)
end

ssm.start(ssm.entry)
