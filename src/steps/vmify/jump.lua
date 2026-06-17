-- steps/vmify/jump.lua
-- Helper functions that emit jump assignments into a block.

local A = require "ast"

local Jump = {}

-- pos = id
function Jump.jmp(funcScope, posVar, scope, id)
  scope:addReferenceToHigherScope(funcScope, posVar)
  return A.AssignmentStatement(
    { A.AssignmentVariable(funcScope, posVar) },
    { A.NumberExpression(id) }
  )
end

-- pos = nil  (stop the loop)
function Jump.jmpNil(funcScope, posVar, scope)
  scope:addReferenceToHigherScope(funcScope, posVar)
  return A.AssignmentStatement(
    { A.AssignmentVariable(funcScope, posVar) },
    { A.NilExpression() }
  )
end

-- pos = cond and trueId or falseId
function Jump.jmpCond(funcScope, posVar, scope, condExpr, trueId, falseId)
  scope:addReferenceToHigherScope(funcScope, posVar)
  return A.AssignmentStatement(
    { A.AssignmentVariable(funcScope, posVar) },
    {
      A.OrExpression(
        A.AndExpression(condExpr, A.NumberExpression(trueId)),
        A.NumberExpression(falseId)
      )
    }
  )
end

return Jump
