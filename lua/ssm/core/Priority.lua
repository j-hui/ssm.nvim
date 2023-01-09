--- Order-maintained priorities, based on Dietz and Sleator (1987)'s algorithm,
--- also called the tag-range relabeling algorithm.
---
--- (No, not the complicated one with amortized constant time; this is the
--- simpler algorithm with amortized O(log n) insertion time.)
---
--- The Dietz and Sleator's tag-range relabeling approach still needs to be
--- benchmarked against Bender et al.'s list-range relabeling algorithm, which
--- has the same time complexity and is intuitive to understand. I chose to
--- implement tag-range relabeling first because I had already sketched out the
--- pseudocode for it before.
---
--- References:
---
---   Paul F. Dietz and Daniel D. Sleator. Two Algorithms for Maintaining Order
---   in a List. 1987.
---
---   Michael A. Bender, Richard Cole, Erik D. Demaine, Martin Farach-Colton,
---   and Jack Zito. Two simplified algorithms for maintaining order in a list.
---   2002.

local M = {}

---@alias Label number
--- A label is an integer less than arena.

--- The range of labels chosen for priorities.
---
--- Denoted by M in Dietz and Sleator (1987).
---
--- arena is chosen such that it is the largest number power of 2 on which Lua
--- can reliably perform integer arithmetic, i.e., less than 1+e14
--- (see: https://www.lua.org/pil/2.3.html).
---
--- Dietz & Sleator's algorithm relies on modulus working as expected, i.e.,:
---
---    forall (i: integer) s.t. i < arena, (i + arena) % arena == i
---
--- In fact, upon experimentation this appears to hold for all m < 90:
---
---    forall (i: integer) s.t. i < arena, (i + m * arena) % arena == i
---
--- This library supports at most ceiling(arena^0.5) - 1 distinct priorities.
local arena = 2 ^ 46

---@class Priority
---
--- Priorities are maintained in a circular linked list around a fixed base
--- priority. This list is doubly-linked to support constant-time deletion.
---
---@field private label number: value to be compared for O(1) time order queries
---@field private next Priority: next priority in the linked list
---@field private prev Priority: previous priority in the linked list
---@field private base BasePriority: the base priority of the total order
local Priority = {}
Priority.__index = Priority

---@class BasePriority : Priority
---@field total number: the total number of priorities assigned under this base

--- Construct a priority with a fresh basis.
---
--- Note that priorities with different bases cannot be compared.
---
---@return BasePriority
function M.New()
  local base = {
    label = 0, -- chosen arbitrarily, just like the paper
    total = 0,
  }
  base.base = base
  base.next = base
  base.prev = base
  setmetatable(base, Priority)
  return base
end

--- Whether two priorities are ordered.
---
--- a < b means a has a higher priority than b.
---
---@param a Priority
---@param b Priority
---@return boolean
function Priority.__lt(a, b)
  if a.base ~= b.base then
    return false
  end
  return a:relative() < b:relative()
end

--- The label of a priority relative to its base.
---
--- Denoted by v_b(r) in Dietz and Sleator (1987), where b is the base and r is
--- self.
---@return Label
---@private
function Priority:relative()
  return (self.label - self.base.label) % arena
end

--- Construct a new priority ordered immediately after self
---
--- That is, p < p:Insert()
---
--- Uses Dietz and Sleator's tag-range relabeling algorithm to relabel
--- successive priorities.
---
---@return Priority: ordered after self
function Priority:Insert()

  -- First, relabel successive priorities to evently distribute labels.
  local function weight(p, i)
    if i >= self.base.total then
      return arena
    end
    return (p.label - self.label) % arena
  end

  local j, k, l, p

  j, p = 1, self.next
  while weight(p, j) <= j ^ 2 do
    j, p = j + 1, p.next
  end

  -- j is now the index up to which we need to relabel; l is its weight.
  l = weight(p, j)

  k, p = 1, self.next
  while k < j do
    p.label = (math.floor(l * j / k) + self.label) % arena
    k, p = k + 1, p.next
  end

  -- Done with relabeling, now we create a new object to insert after self.

  local next_label
  if self.next == self.base then
    next_label = arena
  else
    next_label = self.next:relative()
  end

  local obj = {
    label = math.floor((self.label + next_label) / 2),
    base = self.base,
    next = self.next,
    prev = self,
  }
  self.next.prev = obj
  self.next = obj
  setmetatable(obj, Priority)
  self.base.total = self.base.total + 1
  return obj
end

--- Delete a priority from its base.
---
--- A deleted priority is no longer valid to use.
function Priority:Delete()
  self.base.total = self.base.total - 1
  self.prev.next = self.next
  self.next.prev = self.prev

  -- Turn self into an empty object
  for k in pairs(self) do
    self[k] = nil
  end
end

return M
