-- Adapted from: https://github.com/Roblox/Wiki-Lua-Libraries/blob/master/StandardLibraries/PriorityQueue.lua
-- Notable changes in this adaptation:
-- - Fewer methods
-- - Documented using Sumneko annotations.

local M = {}

---@class PriorityQueue
---
---@generic V                       The type of values.
---@generic P                       The type of priorities.
---@field package values      any   Array of values in binary heap.
---@field package priorities  any   Array of priorities associated with values.
---@field package compare     fun(l: any, r: any): boolean Comparator for priorities
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

M.PriorityQueue = PriorityQueue

local function Defaultcompare(a, b)
  if a < b then
    return true
  else
    return false
  end
end

---@package
--- Percolate the value at the given index up the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param index V             The index of the value to sift.
local function siftUp(queue, index)
  local parentIndex
  if index ~= 1 then
    parentIndex = math.floor(index / 2)
    if queue.compare(queue.priorities[parentIndex], queue.priorities[index]) then
      queue.values[parentIndex], queue.priorities[parentIndex], queue.values[index], queue.priorities[index] =
      queue.values[index], queue.priorities[index], queue.values[parentIndex], queue.priorities[parentIndex]
      siftUp(queue, parentIndex)
    end
  end
end

---@package
--- Percolate the value at teh given index down the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param index V             The index of the value to sift.
local function siftDown(queue, index)
  local lcIndex, rcIndex, minIndex
  lcIndex = index * 2
  rcIndex = index * 2 + 1
  if rcIndex > #queue.values then
    if lcIndex > #queue.values then
      return
    else
      minIndex = lcIndex
    end
  else
    if not queue.compare(queue.priorities[lcIndex], queue.priorities[rcIndex]) then
      minIndex = lcIndex
    else
      minIndex = rcIndex
    end
  end

  if queue.compare(queue.priorities[index], queue.priorities[minIndex]) then
    queue.values[minIndex], queue.priorities[minIndex], queue.values[index], queue.priorities[index] =
    queue.values[index], queue.priorities[index], queue.values[minIndex], queue.priorities[minIndex]
    siftDown(queue, minIndex)
  end
end

--- Construct a new priority queue.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   The newly constructed queue.
function PriorityQueue.New(comparator)
  local newQueue = {}

  if comparator then
    newQueue.compare = comparator
  else
    newQueue.compare = Defaultcompare
  end

  newQueue.values = {}
  newQueue.priorities = {}

  setmetatable(newQueue, PriorityQueue)

  return newQueue
end

--- Create a copy of self, referring to the same values and priorities.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   A copy of the queue.
function PriorityQueue:Clone()
  local newQueue = PriorityQueue.New(self.compare)
  for i = 1, #self.values do
    table.insert(newQueue.values, self.values[i])
    table.insert(newQueue.priorities, self.priorities[i])
  end
  return newQueue
end

--- Add a new value to a priority queue with a given priority.
---
---@generic V             The type of values.
---@generic P             The type of priorities.
---@param   newValue V    The value to add to self.
---@param   priority P    The priority associated with newValue.
function PriorityQueue:Add(newValue, priority)
  table.insert(self.values, newValue)
  table.insert(self.priorities, priority)

  if #self.values <= 1 then
    return
  end

  siftUp(self, #self.values)
end

--- Pop the highest (least) priority item from the queue.
---
---@generic V       The type of values.
---@generic P       The type of priorities.
---@return  V|nil   The highest (least) priority item.
---@return  P|nil   The priority of the highest (least) priority item.
function PriorityQueue:Pop()
  if #self.values <= 0 then
    return nil, nil
  end

  local returnVal, returnPriority = self.values[1], self.priorities[1]
  self.values[1], self.priorities[1] = self.values[#self.values], self.priorities[#self.priorities]
  table.remove(self.values, #self.values)
  table.remove(self.priorities, #self.priorities)
  if #self.values > 0 then
    siftDown(self, 1)
  end

  return returnVal, returnPriority
end

--- Peek at the highest (least) priority item in the queue.
---
--- The queue is left unmodified.
---
---@generic V       The type of values.
---@generic P       The type of priorities.
---@return  V|nil   The highest (least) priority item.
---@return  P|nil   The priority of the highest (least) priority item.
function PriorityQueue:Peek()
  if #self.values > 0 then
    return self.values[1], self.priorities[1]
  else
    return nil, nil
  end
end

--- Export the binary heap as an array.
---
---@generic V         The type of values.
---@generic P         The type of priorities.
---@return  V[]|nil   An array of values.
---@return  P[]|nil   An array of priorities.
function PriorityQueue:AsTable()
  if not self.values or #self.values < 1 then
    return nil, nil
  end

  local vals = {}
  local pris = {}

  for i = 1, #self.values do
    table.insert(vals, self.values[i])
    table.insert(pris, self.priorities[i])
  end

  return vals, pris
end

--- Render a priority queue as human-readable string.
---
---@param   withPriorities  boolean|nil   Whether to render priorities.
---@return  string                        The queue formatted as a string.
function PriorityQueue:ToString(withPriorities)
  local out = ""
  for i = 1, #self.values do
    out = out .. tostring(self.values[i])
    if withPriorities then
      out = out .. "(" .. tostring(self.priorities[i]) .. ")"
    end
    out = out .. " "
  end
  return out
end

--- Obtain the number of values stored in the priority queue.
---
---@return integer  The number of elements stored in the priority queue.
function PriorityQueue:Size()
  return #self.values
end

--- String metamethod.
---
---@return string
function PriorityQueue:__str()
  return self:ToString()
end

--- Length metamethod.
---
---@return integer
function PriorityQueue:__len()
  return self:Size()
end

return M
