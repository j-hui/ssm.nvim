---@diagnostic disable: unused-local
-- local priority = require("figet.core.priority")

local channel = {}

local Channel = {}
Channel.__index = Channel
channel.Channel = Channel

function Channel:new(obj_val, cur_time)
  local chan = {
    __value = {},
    __last = {},
    __later = {},
    __triggers = {},
    __index = self.get,
    __newindex = self.set,
  }

  for k, v in pairs(obj_val) do
    chan.__value[k] = v
    chan.__last[k] = cur_time
  end

  setmetatable(chan, self)
  chan.__object = setmetatable({}, chan)
  return chan
end

function channel.new(obj_val, cur_time)
  return Channel:new(obj_val, cur_time).__object
end

function Channel:get(k)
  return self.__value[k]
end

function channel.get(o, k)
  getmetatable(o):get(k)
end

function Channel:set(k, v)
  self.__value[k] = v
  -- TODO: process triggers
end

function channel.set(o, k, v)
  getmetatable(o):set(k, v)
end

function Channel:last(k)
  if k == nil then
    -- Look for latest last-updated time
    local t = 0
    for _, v in pairs(self.__last) do
      if v > t then
        t = v
      end
    end
    return t
  else
    return self.last[k]
  end
end

function channel.last(o, k)
  getmetatable(o):last(k)
end

function Channel:wait(k)
  -- if k == nil then
  --   -- TODO: wait on any update
  -- else
  --   -- TODO: wait on key
  -- end
end

function channel.wait(o)
  getmetatable(o):wait()
end

function Channel:after(d, k, v)
  self.later[k] = {d, v}
  -- TODO: schedule for later
end

function channel.after(o, d, k, v)
  getmetatable(o):after(d, k, v)
end
