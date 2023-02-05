package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }
local uv = require("luv")

local bouncing_ball = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}

function ssm.clock(clk)
  while clk.period do
    ssm.after(clk.period, clk).tick = true
    ssm.wait(clk)
  end
end

local function make_clock(period)
  local clk = ssm.Channel { period = period }
  ssm.clock:defer(clk)
  return clk
end

function ssm.main()
  local stdin, stdout = ssm.io.get_stdin("tty"), ssm.io.get_stdout("tty")
  assert(stdin, "could not open stdin as tty")
  assert(stdout, "could not open stdout as tty")

  -- NOTE: this puts the terminal in raw mode, which disables terminal handling
  -- of Ctrl-c, Ctrl-z, etc, so it will seem unresponsive unless the terminal is
  -- reset using tty_reset_mode().
  --
  -- We enable raw mode here because we want to handle keystrokes immediately,
  -- and also so that we don't echo them.
  stdin.stream:set_mode(1)

  local clk = make_clock(ssm.msec(100))
  local idx = 1

  stdout.data = "Press j/k to decrease/increase speed; press q to exit.\n"

  for _ = 0, 1000 do
    local clk_updated, stdin_updated = ssm.wait(clk, stdin)

    if not stdin.data then
      break
    end

    if stdin_updated then
      if stdin.data == "j" then
        clk.period = clk.period * 2
      elseif stdin.data == "k" then
        clk.period = math.max(clk.period / 2, ssm.usec(100))
      elseif stdin.data == "q" then
        break
      end
    end

    if clk_updated then
      stdout.data = "\r" .. bouncing_ball[idx]
      idx = (idx % #bouncing_ball) + 1
    end
  end

  uv.tty_reset_mode()
  stdin.data = nil
  stdout.data = nil
  clk.period = nil
end

ssm.start(ssm.main)
