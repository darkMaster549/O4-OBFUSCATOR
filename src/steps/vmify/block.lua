-- steps/vmify/block.lua

local S = require "scope"

local Block = {}
Block.__index = Block

-- Constructor: Block.create(funcScope)
function Block.create(funcScope)
  local self = setmetatable({}, Block)
  self._funcScope = funcScope
  self._blocks    = {}
  self._usedIds   = {}
  return self
end

-- Generate a unique random block id
function Block:newId()
  local id
  repeat
    id = math.random(1, 2^24)
  until not self._usedIds[id]
  self._usedIds[id] = true
  return id
end

-- Create a new block with a fresh child scope
function Block:newBlock()
  local id = self:newId()
  local sc = S:new(self._funcScope)
  local b  = { id = id, stmts = {}, scope = sc }
  table.insert(self._blocks, b)
  return b
end

-- Add a statement to a block
function Block.addStmt(block, stmt)
  table.insert(block.stmts, stmt)
end

-- Return sorted block list
function Block:sorted()
  local list = {}
  for i, b in ipairs(self._blocks) do list[i] = b end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

return Block
