--- A stack implementation whose interface guarantees constant-time operations.

---@class Stack
---
--- A Stack is an array coupled with a length (i.e., a vector).
---
---
---@field private len integer: the number of items stored in the stack
---@field private stack any[]: array of data stored in the stack
local Stack = {}
Stack.__index = Stack

--- Construct an empty stack.
---
---@generic T
---@return Stack
function Stack:New()
  return setmetatable({
    len = 0,
    stack = {},
  }, self)
end

--- Push an item onto the stack.
---
---@generic T
---@param elem T
function Stack:Push(elem)
  if elem == nil then
    -- Refuse to push nil elements.
    return
  end

  self.len = self.len + 1
  self.stack[self.len] = elem
end

--- Pop an item from the stack.
---
---@generic T
---@return T|nil
function Stack:Pop()
  if self:IsEmpty() then
    return nil
  end

  local elem = self.stack[self.len]
  self.stack[self.len] = nil
  self.len = self.len - 1
  return elem
end

--- Peek at the item at the top of the stack.
---
---@generic T
---@return T
function Stack:Peek()
  return self.stack[self.len]
end

--- Whether the stack is empty.
---
---@return boolean
function Stack:IsEmpty()
  return self.len == 0
end

--- Number of items in the stack.
---
---@return integer
function Stack:__len()
  return self.len
end

return Stack
