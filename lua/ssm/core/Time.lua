local M = {}

---@class Duration: integer       Relative time
---
---@operator add(Time): Time

---@class Timestamp: integer|nil  Timestamps for both physical and logical time

---@class Time: Timestamp         Logical timestamps
---
---@operator add(Time): Time
---@operator add(Duration): Time

---@class PhysTime: Timestamp   Physical timestamps
---
---@operator add(PhysTime): PhysTime
---@operator add(Duration): PhysTime

--- Bottom element of logical timestamps.
---@type Time
M.NEVER = nil

--- Return the minimum of two timestamps.
---
---@generic T: Timestamp
---@param l T
---@param r T
---@return  T
function M.min(l, r)
  if l == M.NEVER then
    return r
  elseif r == M.NEVER then
    return l
  else
    return math.min(l, r)
  end
end

--- Whether a timestamp is greater than another.
---
---@generic T: Timestamp
---@param l T
---@param r T
---@return  boolean
function M.lt(l, r)
  if l == M.NEVER then
    return false
  elseif r == M.NEVER then
    return true
  else
    return l < r
  end
end

return M
