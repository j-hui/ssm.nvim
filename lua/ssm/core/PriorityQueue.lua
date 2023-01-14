-- Adapted from: https://github.com/Roblox/Wiki-Lua-Libraries/blob/master/StandardLibraries/PriorityQueue.lua
--
-- Notable changes in this adaptation:
-- - Fewer methods
-- - Documented using Sumneko annotations.
-- - Simply uses < instead of comparator (since < maybe overloaded anyway)
-- - Iterative sifting implementation rather than recursive

local M = {}

---@class PriorityQueue
---
---@generic V                       The type of values.
---@generic P                       The type of priorities.
---@field package values      any   Array of values in binary heap.
---@field package priorities  any   Array of priorities associated with values.
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

M.PriorityQueue = PriorityQueue

---@package
--- Percolate the value at the given index up the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param index V             The index of the value to sift.
local function siftUp(queue, index)

  -- Keep traversing up the tree until either:
  -- - index is the root of the tree, or
  -- - index is in its rightful place wrt its parent.
  while index > 1 do

    -- Compute the parent of index
    local parentIndex = math.floor(index / 2)

    if queue.priorities[parentIndex] < queue.priorities[index] then

      -- Swap values/priorities at parentIndex and index
      queue.values[parentIndex], queue.priorities[parentIndex],
          queue.values[index], queue.priorities[index] =

      queue.values[index], queue.priorities[index],
          queue.values[parentIndex], queue.priorities[parentIndex]

      -- Traverse up
      index = parentIndex

    else
      -- element at index is at its rightful place, we are done.
      break
    end
  end

  -- Original recursive implementation:
  -- if index ~= 1 then
  --   parentIndex = math.floor(index / 2)
  --   if queue.priorities[parentIndex] < queue.priorities[index] then
  --     queue.values[parentIndex], queue.priorities[parentIndex], queue.values[index], queue.priorities[index] =
  --     queue.values[index], queue.priorities[index], queue.values[parentIndex], queue.priorities[parentIndex]
  --     siftUp(queue, parentIndex)
  --   end
  -- end
end

---@package
--- Percolate the value at the given index down the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param index V             The index of the value to sift.
local function siftDown(queue, index)

  -- Keep traversing down the tree until either:
  -- - index is a leaf of the tree, or
  -- - index is in its rightful place wrt its children.
  while true do

    -- Pick smallest child of index
    local minIndex

    -- Indices of children
    local lcIndex, rcIndex = index * 2, index * 2 + 1

    if rcIndex > #queue.values then -- No right child
      if lcIndex > #queue.values then -- No left child
        return -- index is a leaf
      else
        minIndex = lcIndex -- Pick only child, left
      end
    else
      -- Note: because we always populate the min heap from left to right
      -- (i.e., indices are dense), if we have a right child, there will always
      -- be a left child.
      --
      -- In other words, rcIndex > #queue.values implies
      -- lcIndex > #queue.values, so we don't need to check the latter.
      if queue.priorities[lcIndex] < queue.priorities[rcIndex] then
        minIndex = rcIndex -- Right child is smaller
      else
        minIndex = lcIndex -- Left child is smaller
      end
    end

    if queue.priorities[index] < queue.priorities[minIndex] then

      -- Swap elements at minIndex and index
      queue.values[minIndex], queue.priorities[minIndex],
          queue.values[index], queue.priorities[index] =

      queue.values[index], queue.priorities[index],
          queue.values[minIndex], queue.priorities[minIndex]

      -- Traverse down
      index = minIndex
    else
      -- element at index is at its rightful place, we are done.
      break
    end
  end

  -- Original recursive implementation:
  -- local lcIndex, rcIndex, minIndex
  -- lcIndex = index * 2
  -- rcIndex = index * 2 + 1
  -- if rcIndex > #queue.values then
  --   if lcIndex > #queue.values then
  --     return
  --   else
  --     minIndex = lcIndex
  --   end
  -- else
  --   if queue.priorities[lcIndex] < queue.priorities[rcIndex] then
  --     minIndex = rcIndex
  --   else
  --     minIndex = lcIndex
  --   end
  -- end
  --
  -- if queue.priorities[index] < queue.priorities[minIndex] then
  --
  --   queue.values[minIndex], queue.priorities[minIndex],
  --     queue.values[index], queue.priorities[index] =
  --
  --   queue.values[index], queue.priorities[index],
  --     queue.values[minIndex], queue.priorities[minIndex]
  --
  --   siftDown(queue, minIndex)
  -- end
end

--- Default (empty) constructor for priority queues.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   The newly constructed queue.
function PriorityQueue.New()
  return setmetatable({ values = {}, priorities = {} }, PriorityQueue)
end

--- Copy constructor for priority queues.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   A copy of the queue.
function PriorityQueue:Clone()
  local newQueue = PriorityQueue.New()
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
