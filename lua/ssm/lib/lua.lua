local M = {}

--- Forwards-compatible implementation of unpack that uses overloaded __index.
---
--- The builtin unpack() doesn't work with tables whose __index is overloaded.
---
---@param t table
---@param i number|nil
---@return any ...
function M.unpack(t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], M.unpack(t, i + 1)
  end
end

local rawpairs = pairs

--- Fowards-compatible implementation of pairs that uses overloaded __pairs.
---
---@generic K
---@generic V
---
---@param t table<K,V>                              table
---@return fun(table: table<K, V>, i: integer): V   iterator
---@return table<K, V>                              state
---@return nil                                      index
function M.pairs(t)
  local m = getmetatable(t)
  local p = m and m.__pairs or rawpairs
  return p(t)
end

local rawipairs = ipairs

--- Fowards-compatible implementation of pairs that uses overloaded __ipairs.
---
---@generic T
---
---@param t T[]                                   array
---@return fun(table: T[], i: integer): integer   iterator
---@return T[]                                    state
---@return integer                                index
function M.ipairs(t)
  local m = getmetatable(t)
  local p = m and m.__ipairs or rawipairs
  return p(t)
end

return M
