-- steps/vmify/builder.lua

local A        = require "ast"
local S        = require "scope"
local Block    = require "steps.vmify.block"
local Jump     = require "steps.vmify.jump"
local Compiler = require "steps.vmify.compiler"
local Dispatch = require "steps.vmify.dispatch"

local Builder = {}

function Builder.build(ast)
  local originalGlobal = ast.globalScope
  local funcScope = S:new(originalGlobal)
  local posVar = funcScope:addVariable()

  local blockMgr = Block.create(funcScope)
  local compiler = Compiler.new(blockMgr, funcScope, posVar)

  local startBlock = blockMgr:newBlock()

  -- grab original statements BEFORE we touch ast.body
  local originalStatements = ast.body.statements
  local originalBodyScope  = ast.body.scope

  originalBodyScope:setParent(funcScope)

  local finalBlock = compiler:compileBlock(originalStatements, startBlock, nil)

  local last = finalBlock.stmts[#finalBlock.stmts]
  if not last or not last._isVmJump then
    Block.addStmt(finalBlock, Jump.jmpNil(funcScope, posVar, finalBlock.scope))
  end

  local sorted = blockMgr:sorted()

  local dispatchBody = Dispatch.build(sorted, 1, #sorted, funcScope, funcScope, posVar)

  local initPos = A.LocalVariableDeclaration(
    funcScope,
    { posVar },
    { A.NumberExpression(startBlock.id) }
  )

  local whileStmt = A.WhileStatement(
    dispatchBody,
    A.VariableExpression(funcScope, posVar),
    funcScope
  )

  local funcBody = A.Block({ initPos, whileStmt }, funcScope)
  local doStmt   = A.DoStatement(funcBody)

  -- IMPORTANT: replace ast.body statements in-place
  -- so scope references stay valid
  ast.body.statements = { doStmt }
  ast.body.scope = funcScope

  return ast
end

return Builder
