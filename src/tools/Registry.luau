--!strict
local FileSystem = require("./FileSystem")
local Terminal = require("./Terminal")
local Communication = require("./Communication")

local Registry = {}

export type ToolDef = {
    name: string,
    description: string,
    parameters: any,
    execute: (args: any) -> any
}

local tools: {[string]: ToolDef} = {}

function Registry.register(tool: ToolDef)
    tools[tool.name] = tool
end

function Registry.get(name: string): ToolDef?
    return tools[name]
end

function Registry.getAllDefinitions(): {any}
    local defs = {}
    for _, tool in pairs(tools) do
        table.insert(defs, {
            type = "function",
            ["function"] = {
                name = tool.name,
                description = tool.description,
                parameters = tool.parameters
            }
        })
    end
    return defs
end

function Registry.validate(name: string, args: any): (boolean, string?)
    local tool = tools[name]
    if not tool then return false, "Tool not found" end
    
    if tool.parameters and tool.parameters.required then
        for _, reqField in ipairs(tool.parameters.required) do
            if args[reqField] == nil then
                return false, "Missing required argument: " .. reqField
            end
        end
    end
    
    return true
end

function Registry.getToolCount(): number
    local count = 0
    for _ in pairs(tools) do
        count += 1
    end
    return count
end

-- ═══════════════════════════════════════
--  Register All Tools
-- ═══════════════════════════════════════

-- File System
Registry.register(FileSystem.readFileTool)
Registry.register(FileSystem.readFileLinesTool)
Registry.register(FileSystem.writeFileTool)
Registry.register(FileSystem.patchFileTool)
Registry.register(FileSystem.deleteFileTool)
Registry.register(FileSystem.createDirectoryTool)
Registry.register(FileSystem.listFilesTool)

-- Terminal
Registry.register(Terminal.runCommandTool)

-- Search
Registry.register(require("./Ripgrep").searchTool)

-- Communication
Registry.register(Communication.broadcastTool)
Registry.register(Communication.whisperTool)
Registry.register(Communication.requestHelpTool)
Registry.register(Communication.reportProgressTool)

-- Interaction
Registry.register(require("./Interaction").askUserTool)

-- Reasoning
Registry.register(require("./Thinking").thinkTool)

-- Web
Registry.register(require("./WebFetch").fetchTool)

-- Delegation
Registry.register(require("./Delegation").delegateTaskTool)

return Registry
