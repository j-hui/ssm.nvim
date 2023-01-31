-- Adapted from: https://github.com/Roblox/Wiki-Lua-Libraries/blob/master/StandardLibraries/PriorityQueue.lua
--
-- Notable changes in this adaptation:
-- - Fewer methods
-- - Documented using Sumneko annotations.
-- - Simply uses < instead of comparator (since < maybe overloaded anyway)
-- - Iterative sifting implementation rather than recursive
-- - If x < y, x has the higher priority (rather than the other way around)

local ROOT = 1

---@class PriorityQueue
---
--- Elements are compared according to their priorities; when x < y, x has
--- the higher priority (though we call it the "least" element).  In code:
---
---     local x = pq:Pop()
---     local y = pq:Pop()
---     assert(x < y)
---
---@generic V                     The type of values.
---@generic P                     The type of priorities.
---@field package values  any[]   Elements' values in binary heap.
---@field package prios   any[]   Elements' priorities in binary heap.
local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

--- Default (empty) constructor for priority queues.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   The newly constructed queue.
local function new_priority_queue()
  return setmetatable({ values = {}, prios = {} }, PriorityQueue)
end


---@package
--- Percolate the value at the given index up the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param current V           The index of the value to sift.
local function sift_up(queue, current)

  -- Keep traversing up the tree until either:
  -- - current is the root of the tree, or
  -- - current is in its rightful place wrt its parent.
  while current > 1 do

    -- Compute the parent of current
    local parent = math.floor(current / 2)

    if queue.prios[current] < queue.prios[parent] then

      -- Swap values/priorities at parent and current
      queue.values[parent], queue.prios[parent],
          queue.values[current], queue.prios[current] =

      queue.values[current], queue.prios[current],
          queue.values[parent], queue.prios[parent]

      -- Traverse up the tree
      current = parent

    else
      -- parent < current, so current is at its rightful place.
      break
    end
  end
end

---@package
--- Percolate the value at the given index down the binary heap.
---
---@generic     V             The type of values.
---@generic     P             The type of priorities.
---@param queue PriorityQueue The queue to sift.
---@param current V           The index of the value to sift.
local function sift_down(queue, current)

  -- Keep traversing down the tree until either:
  -- - current is a leaf of the tree, or
  -- - current is in its rightful place wrt its children.
  while true do

    -- Pick child with the higher (lower) priority.
    -- That is, if we have two children l and r and r < l, pick r.
    --
    -- Note that because we always populate the min heap from left to right
    -- (i.e., indices are dense), if we have a right child, there will always be
    -- a left child. In other words, if there is no left child, there is no need
    -- to check for a right child.

    -- Start with the left child
    local child = current * 2

    if child > #queue.values then
      -- No left child; current is a leaf
      break
    end

    if child + 1 > #queue.values and -- There is also a right child
        queue.prios[child + 1] < queue.prios[child] --  with higher priority
    then
      -- Pick right child instead
      child = child + 1
    end

    if queue.prios[child] < queue.prios[current] then

      -- Swap elements at child and current
      queue.values[child], queue.prios[child],
          queue.values[current], queue.prios[current] =

      queue.values[current], queue.prios[current],
          queue.values[child], queue.prios[child]

      -- Traverse down the tree
      current = child
    else
      -- current < child, so current is at its rightful place.
      break
    end
  end
end

--- Copy constructor for priority queues.
---
---@generic V               The type of values.
---@generic P               The type of priorities.
---@return  PriorityQueue   A copy of the queue.
function PriorityQueue:clone()
  local queue = new_priority_queue()
  for i = 1, #self.values do
    table.insert(queue.values, self.values[i])
    table.insert(queue.prios, self.prios[i])
  end
  return queue
end

--- Add a new value to a priority queue with a given priority.
---
---@generic V         The type of values.
---@generic P         The type of priorities.
---@param   val   V   The value to add to self.
---@param   prio  P   The priority associated with val.
function PriorityQueue:add(val, prio)
  table.insert(self.values, val)
  table.insert(self.prios, prio)

  if #self.values > ROOT then
    sift_up(self, #self.values)
  end
end

--- Pop the highest (least) priority item from the queue.
---
---@generic V       The type of values.
---@generic P       The type of priorities.
---@return  V|nil   The highest (least) priority item.
---@return  P|nil   The priority of the highest (least) priority item.
function PriorityQueue:pop()
  if #self.values <= 0 then
    return nil, nil
  end

  local val, prio = self.values[ROOT], self.prios[ROOT]

  -- Move last element to root
  self.values[ROOT], self.prios[ROOT] = self.values[#self.values], self.prios[#self.prios]

  table.remove(self.values, #self.values)
  table.remove(self.prios, #self.prios)

  if #self.values > ROOT then
    sift_down(self, ROOT)
  end

  return val, prio
end

--- Reposition a possibly existing element in the queue with a new priority.
---
--- Warning: this method is O(n). Use sparingly!
---
---@generic V         The type of values.
---@generic P         The type of priorities.
---@param   val   V   The value to add to self.
---@param   prio  P   The new priority to associate with val.
function PriorityQueue:reposition(val, prio)
  local index = nil

  for i, v in ipairs(self.values) do
    if v == val then
      index = i
      break
    end
  end

  self.prios[index] = prio

  local child = index * 2
  local lowerThanChild = child < #self.values and self.prios[child] < prio

  if index == ROOT or lowerThanChild then
    sift_down(self, index)
  else
    sift_up(self, index)
  end
end

--- Peek at the highest (least) priority item in the queue.
---
--- The queue is left unmodified.
---
---@generic V       The type of values.
---@generic P       The type of priorities.
---@return  V|nil   The highest (least) priority item.
---@return  P|nil   The priority of the highest (least) priority item.
function PriorityQueue:peek()
  if #self.values <= 0 then
    return nil, nil
  else
    return self.values[1], self.prios[1]
  end
end

--- Export the binary heap as an array.
---
---@generic V         The type of values.
---@generic P         The type of priorities.
---@return  V[]|nil   An array of values.
---@return  P[]|nil   An array of priorities.
function PriorityQueue:as_table()
  if not self.values or #self.values < 1 then
    return nil, nil
  end

  local vals = {}
  local pris = {}

  for i = 1, #self.values do
    table.insert(vals, self.values[i])
    table.insert(pris, self.prios[i])
  end

  return vals, pris
end

--- Render a priority queue as human-readable string.
---
---@param   with_priorities  boolean|nil   Whether to render priorities.
---@return  string                        The queue formatted as a string.
function PriorityQueue:to_string(with_priorities)
  local out = ""
  for i = 1, #self.values do
    out = out .. tostring(self.values[i])
    if with_priorities then
      out = out .. "(" .. tostring(self.prios[i]) .. ")"
    end
    out = out .. " "
  end
  return out
end

--- Obtain the number of values stored in the priority queue.
---
---@return integer  The number of elements stored in the priority queue.
function PriorityQueue:size()
  return #self.values
end

--- String metamethod.
---
---@return string
function PriorityQueue:__str()
  return self:to_string()
end

--- Length metamethod.
---
---@return integer
function PriorityQueue:__len()
  return self:size()
end

return new_priority_queue
