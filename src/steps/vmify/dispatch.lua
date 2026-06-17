-- steps/vmify/dispatch.lua

local A = require "ast"
local S = require "scope"

local Dispatch = {}

function Dispatch.build(list, l, r, parentScope, funcScope, posVar)
  if r < l then
    return A.Block({}, S:new(parentScope))
  end

  if l == r then
    local b = list[l]
    -- Don't re-parent! Just use the block's stmts directly in a new block
    -- under parentScope so reference counts stay intact
    local sc = S:new(parentScope)
    return A.Block(b.stmts, sc)
  end

  local mid     = math.floor((l + r) / 2)
  local bound   = list[mid].id
  local ifScope = S:new(parentScope)
  ifScope:addReferenceToHigherScope(funcScope, posVar)

  local lBlock = Dispatch.build(list, l,     mid,   ifScope, funcScope, posVar)
  local rBlock = Dispatch.build(list, mid+1, r,     ifScope, funcScope, posVar)

  return A.Block({
    A.IfStatement(
      A.LessThanOrEqualsExpression(
        A.VariableExpression(funcScope, posVar),
        A.NumberExpression(bound)
      ),
      lBlock, {}, rBlock
    )
  }, ifScope)
end

return Dispatch
