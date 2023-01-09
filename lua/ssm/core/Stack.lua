-- A stack implementation that guarantees

local Stack = {}
Stack.__index = Stack

function Stack:New()
  return setmetatable({
    len = 0,
    stack = {},
  }, self)
end

function Stack:Push(elem)
  self.len = self.len + 1
  self.stack[self.len] = elem
end

function Stack:Pop()
  local elem = self.stack[self.len]
  self.stack[self.len] = nil
  self.len = self.len - 1
  return elem
end

function Stack:Peek()
  return self.stack[self.len]
end

function Stack:IsEmpty()
  return self.len == 0
end

function Stack:__len()
  return self.len
end

return Stack
