-- steps/vmify/init.lua
-- The Step entry point. Replaces steps/vmify.lua
-- pipeline.lua should require "steps.vmify.init"

local Step    = require "step"
local Builder = require "steps.vmify.builder"

local Vmify = Step:extend()
Vmify.Name        = "Vmify"
Vmify.Description = "Wraps AST into a block-based VM dispatch loop (modular)"
Vmify.SettingsDescriptor = {}

function Vmify:init() end

function Vmify:apply(ast)
  return Builder.build(ast)
end

return Vmify
