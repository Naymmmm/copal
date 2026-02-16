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
Registry.register(FileSystem.moveFileTool)
Registry.register(FileSystem.copyFileTool)
Registry.register(FileSystem.appendFileTool)

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

-- Reasoning & Flow Control
Registry.register(require("./Thinking").thinkTool)
Registry.register(require("./Thinking").sleepTool)
Registry.register(require("./Thinking").wakeTool)
Registry.register(require("./FlowControl").extendIterationsTool)

-- Web
Registry.register(require("./WebFetch").fetchTool)

-- Glob
Registry.register(require("./Glob").globTool)

-- Delegation
Registry.register(require("./Delegation").delegateTaskTool)

local Search = require("./Search")
Registry.register(Search.searchTool)

local MemoryTool = require("./MemoryTool")
Registry.register(MemoryTool.saveMemory)
Registry.register(MemoryTool.recallMemory)

-- Git
local Git = require("./Git")
Registry.register(Git.statusTool)
Registry.register(Git.diffTool)
Registry.register(Git.logTool)
Registry.register(Git.commitTool)

-- Tree
Registry.register(require("./Tree").treeTool)

-- HTTP Request
Registry.register(require("./HttpRequest").requestTool)

-- Multi-Patch
Registry.register(require("./MultiPatch").multiPatchTool)

-- Process Management
local Process = require("./Process")
Registry.register(Process.spawnBackgroundTool)
Registry.register(Process.checkBackgroundTool)
Registry.register(Process.checkPortTool)
Registry.register(Process.killProcessTool)

-- Bookmark
local Bookmark = require("./Bookmark")
Registry.register(Bookmark.bookmarkTool)
Registry.register(Bookmark.listBookmarksTool)
Registry.register(Bookmark.removeBookmarkTool)

-- Hash
Registry.register(require("./Hash").checksumTool)

-- Archive
Registry.register(require("./Archive").readArchiveTool)


function Registry.unregister(name: string)
    tools[name] = nil
end

function Registry.reloadMCP()
    -- 1. Unregister existing MCP tools
    for name, _ in pairs(tools) do
        if name:sub(1, 4) == "mcp_" then
            tools[name] = nil
        end
    end

    -- 2. Load from Config
    local MCP = require("../core/MCP")
    local Config = require("../lib/Config")
    Config.load() -- Reload from disk to get latest changes

    local Task = require("@lune/task")
    local Logger = require("../lib/Logger")

    if Config.mcpServers then
        for name, serverConfig in pairs(Config.mcpServers) do
            local client = MCP.new(name, serverConfig)

            -- Connect with a timeout to avoid freezing the UI
            local connected = false
            local timedOut = false

            local worker = Task.spawn(function()
                if client:connect() and client:initialize() then
                    connected = true
                end
            end)

            local start = os.clock()
            while not connected and os.clock() - start < 10 do
                if timedOut then break end
                Task.wait(0.1)
            end

            if not connected then
                timedOut = true
                Logger.warn("MCP server '" .. name .. "' failed to connect within 10s, skipping.")
                continue
            end

            local ok, serverTools = pcall(function() return client:listTools() end)
            if not ok or not serverTools or #serverTools == 0 then
                Logger.warn("MCP server '" .. name .. "' connected but returned no tools.")
                continue
            end

            for _, tool in ipairs(serverTools) do
                local mcpTool = {
                    name = "mcp_" .. name .. "_" .. tool.name,
                    description = tool.description or ("Tool from " .. name),
                    parameters = tool.inputSchema,
                    execute = function(args)
                        return client:callTool(tool.name, args)
                    end
                }
                Registry.register(mcpTool)
            end
            Logger.info("MCP server '" .. name .. "' loaded " .. #serverTools .. " tool(s).")
        end
    end
end

-- Initial Load
Registry.reloadMCP()

return Registry
