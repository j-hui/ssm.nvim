package.path = './?/init.lua;./?.lua;' .. package.path
local ssm = require("ssm") { backend = "luv" }
local uv = require("luv")

local spinners = require("spinners")

local animations = {}
for _, s in pairs(spinners) do
  table.insert(animations, s)
end

function ssm.clock(clk)
  while clk.period do
    clk:after(clk.period, { tick = true })
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

  -- NOTE: this puts the terminal in raw mode to handle keystrokes immediately,
  -- i.e., to prevent the terminal from buffering stdin until <CR> or <C-d>.
  --
  -- However, this also disables terminal handling of <C-c>, <C-z>, etc., and
  -- also turns of terminal echo, so we need to handle these manually.
  stdin.stream:set_mode(1)

  local clk = make_clock(ssm.msec(200))
  local frame = 1
  local animation = 1

  stdout.data = [[
Mappings:

  j/<C-d>   decrease frame rate
  k/<C-u>   increase frame rate
  h         previous animation
  l         next animation
  q/<C-c>   exit

]] .. "\27[?25l" -- ANSI code to hide cursor

  while true do
    local clk_updated, stdin_updated = ssm.wait(clk, stdin)

    if stdin_updated then
      if not stdin.data then
        break
      end

      local byte = string.byte(stdin.data)
      if stdin.data == "j"
          or byte == 4 -- ctrl-d
      then
        clk.period = clk.period * 2
      elseif stdin.data == "k"
          or byte == 21 -- ctrl-u
      then
        -- Stay just above 1ms, the smallest period supported by luv
        clk.period = math.max(clk.period / 2, ssm.usec(1050))
      elseif stdin.data == "h"
      then
        animation = animation - 1
        animation = animation == 0 and #animations or animation
        frame = 1
      elseif stdin.data == "l"
      then
        animation = (animation % #animations) + 1
        frame = 1
      elseif stdin.data == "q"
          or byte == 26 -- ctrl-z
          or byte == 3 -- ctrl-c
      then
        break
      end
    end

    if clk_updated then
      -- ANSI sequence to clear line and revert cursor to beginning
      -- before printing animation frame
      local clear_line = "\27[2K\r"
      local time = string.format("Time: %9.2fus", ssm.as_usec(ssm.now()))
      local info = string.format("Frame period: %9.2fus", ssm.as_usec(clk.period))
      stdout.data = string.format("%s%s\t%s\t%s", clear_line, time, info, animations[animation][frame])
      frame = (frame % #animations[animation]) + 1
    end
  end

  uv.tty_reset_mode()
  stdin.data = nil
  stdout.data = nil
  clk.period = nil
end

ssm.start(ssm.main)
