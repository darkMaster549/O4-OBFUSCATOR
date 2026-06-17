-- steps/vmify/compiler.lua

local A     = require "ast"
local Block = require "steps.vmify.block"
local Jump  = require "steps.vmify.jump"

local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(blockMgr, funcScope, posVar)
  local self = setmetatable({}, Compiler)
  self.blockMgr  = blockMgr
  self.funcScope = funcScope
  self.posVar    = posVar
  self.hoisted   = {}  -- list of hoisted local decls
  return self
end

function Compiler:jmp(scope, id)
  return Jump.jmp(self.funcScope, self.posVar, scope, id)
end

function Compiler:jmpNil(scope)
  return Jump.jmpNil(self.funcScope, self.posVar, scope)
end

function Compiler:jmpCond(scope, cond, tId, fId)
  return Jump.jmpCond(self.funcScope, self.posVar, scope, cond, tId, fId)
end

function Compiler:newBlock()
  return self.blockMgr:newBlock()
end

local function blockHasJump(block)
  local stmts = block.stmts
  if #stmts == 0 then return false end
  return stmts[#stmts]._isVmJump == true
end

function Compiler:taggedJmp(scope, id)
  local s = self:jmp(scope, id)
  s._isVmJump = true
  return s
end

function Compiler:taggedJmpNil(scope)
  local s = self:jmpNil(scope)
  s._isVmJump = true
  return s
end

function Compiler:taggedJmpCond(scope, cond, tId, fId)
  local s = self:jmpCond(scope, cond, tId, fId)
  s._isVmJump = true
  return s
end

function Compiler:addJumpIfNeeded(block, targetId)
  if not blockHasJump(block) then
    Block.addStmt(block, self:taggedJmp(block.scope, targetId))
  end
end

function Compiler:addNilIfNeeded(block)
  if not blockHasJump(block) then
    Block.addStmt(block, self:taggedJmpNil(block.scope))
  end
end

function Compiler:compileBlock(stmtList, curBlock, exitBlock)
  for _, stmt in ipairs(stmtList) do
    curBlock = self:compileStmt(stmt, curBlock, exitBlock)
  end
  return curBlock
end

function Compiler:compileStmt(stmt, curBlock, exitBlock)
  local k  = stmt.kind
  local sc = curBlock.scope

  -- Hoist local variable declarations to funcScope
  if k == "LocalVariableDeclaration" then
    -- move variable ids to funcScope
    for _, id in ipairs(stmt.ids) do
      self.funcScope:addIfNotExists(id)
    end
    -- if there are expressions, emit as assignment
    if stmt.expressions and #stmt.expressions > 0 then
      local lhs = {}
      for _, id in ipairs(stmt.ids) do
        local av = A.AssignmentVariable(self.funcScope, id)
        table.insert(lhs, av)
      end
      local assign = A.AssignmentStatement(lhs, stmt.expressions)
      Block.addStmt(curBlock, assign)
    end
    return curBlock

  elseif k == "LocalFunctionDeclaration" then
    -- hoist to funcScope too
    self.funcScope:addIfNotExists(stmt.id)
    -- convert to function declaration
    local funcDecl = A.FunctionDeclaration(
      self.funcScope, stmt.id, {}, stmt.args, stmt.body
    )
    Block.addStmt(curBlock, funcDecl)
    return curBlock

  elseif k == "IfStatement" then
    local finalBlock = self:newBlock()

    local function buildChain(cond, body, elseifs, elsebody)
      local trueBlock = self:newBlock()
      local nextBlock

      if #elseifs > 0 or elsebody then
        nextBlock = self:newBlock()
      else
        nextBlock = finalBlock
      end

      Block.addStmt(curBlock, self:taggedJmpCond(sc, cond, trueBlock.id, nextBlock.id))

      local afterTrue = self:compileBlock(body.statements, trueBlock, finalBlock)
      self:addJumpIfNeeded(afterTrue, finalBlock.id)

      curBlock = nextBlock
      sc = curBlock.scope

      for i, eif in ipairs(elseifs) do
        local eifTrue = self:newBlock()
        local eifNext
        if i < #elseifs or elsebody then
          eifNext = self:newBlock()
        else
          eifNext = finalBlock
        end
        Block.addStmt(curBlock, self:taggedJmpCond(sc, eif.condition, eifTrue.id, eifNext.id))
        local afterEif = self:compileBlock(eif.body.statements, eifTrue, finalBlock)
        self:addJumpIfNeeded(afterEif, finalBlock.id)
        curBlock = eifNext
        sc = curBlock.scope
      end

      if elsebody then
        local afterElse = self:compileBlock(elsebody.statements, curBlock, finalBlock)
        self:addJumpIfNeeded(afterElse, finalBlock.id)
      else
        if curBlock ~= finalBlock then
          self:addJumpIfNeeded(curBlock, finalBlock.id)
        end
      end
    end

    buildChain(stmt.condition, stmt.body, stmt.elseifs or {}, stmt.elsebody)
    return finalBlock

  elseif k == "WhileStatement" then
    local checkBlock = self:newBlock()
    local bodyBlock  = self:newBlock()
    local finalBlock = self:newBlock()

    Block.addStmt(curBlock, self:taggedJmp(sc, checkBlock.id))
    Block.addStmt(checkBlock, self:taggedJmpCond(checkBlock.scope, stmt.condition, bodyBlock.id, finalBlock.id))

    local afterBody = self:compileBlock(stmt.body.statements, bodyBlock, finalBlock)
    self:addJumpIfNeeded(afterBody, checkBlock.id)

    return finalBlock

  elseif k == "RepeatStatement" then
    local bodyBlock  = self:newBlock()
    local finalBlock = self:newBlock()

    Block.addStmt(curBlock, self:taggedJmp(sc, bodyBlock.id))

    local afterBody = self:compileBlock(stmt.body.statements, bodyBlock, finalBlock)
    if not blockHasJump(afterBody) then
      Block.addStmt(afterBody, self:taggedJmpCond(afterBody.scope, stmt.condition, finalBlock.id, bodyBlock.id))
    end

    return finalBlock

  elseif k == "ForStatement" then
    local finalBlock = self:newBlock()
    Block.addStmt(curBlock, stmt)
    self:addJumpIfNeeded(curBlock, finalBlock.id)
    return finalBlock

  elseif k == "ForInStatement" then
    local finalBlock = self:newBlock()
    Block.addStmt(curBlock, stmt)
    self:addJumpIfNeeded(curBlock, finalBlock.id)
    return finalBlock

  elseif k == "DoStatement" then
    return self:compileBlock(stmt.body.statements, curBlock, exitBlock)

  elseif k == "BreakStatement" then
    if exitBlock then
      Block.addStmt(curBlock, self:taggedJmp(sc, exitBlock.id))
    else
      Block.addStmt(curBlock, self:taggedJmpNil(sc))
    end
    return self:newBlock()

  elseif k == "ReturnStatement" then
    Block.addStmt(curBlock, stmt)
    Block.addStmt(curBlock, self:taggedJmpNil(sc))
    return self:newBlock()

  else
    Block.addStmt(curBlock, stmt)
    return curBlock
  end
end

return Compiler
