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
                -- Check for aliases if standard field missing (legacy support)
                -- This is specific to our implementation where we might have loose schemas
                return false, "Missing required argument: " .. reqField
            end
        end
    end
    
    return true
end

-- Initialize default tools
Registry.register(FileSystem.readFileTool)
Registry.register(FileSystem.writeFileTool)
Registry.register(FileSystem.listFilesTool)
Registry.register(Terminal.runCommandTool)
Registry.register(Communication.broadcastTool)

return Registry
