--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local Task = require("@lune/task")
local Logger = require("../lib/Logger")

export type MCPServerConfig = {
    command: string,
    args: {string},
    env: {[string]: string}?
}

local MCPClient = {}
MCPClient.__index = MCPClient

function MCPClient.new(name: string, config: MCPServerConfig)
    local self = setmetatable({}, MCPClient)
    self.name = name
    self.config = config
    self.child = nil :: any
    self.requestId = 0
    self.pendingRequests = {} :: {[number]: (any) -> ()}
    self.capabilities = {}
    return self
end

function MCPClient:connect()
    Logger.info("Connecting to MCP server: " .. self.name)
    
    local success, child = pcall(function()
        return process.create(self.config.command, self.config.args)
    end)

    if not success then
        Logger.error("Failed to spawn MCP server '" .. self.name .. "': " .. tostring(child))
        return false
    end

    if not child then
        Logger.error("Failed to spawn MCP server '" .. self.name .. "': process returned nil")
        return false
    end
    
    -- Verify it's a child handle (userdata)
    if type(child) ~= "userdata" then
        Logger.error("Process spawn returned result instead of handle. MCP requires streaming support.")
        return false
    end
    
    self.child = child
    
    -- Start Reader Loops
    Task.spawn(function()
        self:readLoop()
    end)
    
    Task.spawn(function()
        if self.child.stderr then
             local errChunk = self.child.stderr:read()
             while errChunk do
                 Logger.warn("MCP STDERR (" .. self.name .. "): " .. errChunk)
                 errChunk = self.child.stderr:read()
             end
        end
    end)
    
    return true
end

function MCPClient:readLoop()
    local buffer = ""
    while self.child do
        -- Read chunk
        local chunk = self.child.stdout:read()
        if not chunk then
            Logger.warn("MCP server " .. self.name .. " stdout closed.")
            break
        end
        
        buffer = buffer .. chunk
        
        -- Process lines
        while true do
            local newline = buffer:find("\n")
            if not newline then break end
            
            local line = buffer:sub(1, newline - 1)
            buffer = buffer:sub(newline + 1)
            
            if #line > 0 then
                self:handleMessage(line)
            end
        end
        
        Task.wait(0.05) -- Yield
    end
end

function MCPClient:handleMessage(line: string)
    local success, msg = pcall(function() return serde.decode("json", line) end)
    if not success then
        Logger.warn("MCP (" .. self.name .. "): Failed to decode JSON: " .. line:sub(1, 100))
        return
    end

    if msg.id and self.pendingRequests[msg.id] then
        -- Response to request
        local callback = self.pendingRequests[msg.id]
        self.pendingRequests[msg.id] = nil
        callback(msg)
    elseif msg.method and msg.method:sub(1, 13) == "notifications" then
        Logger.debug("MCP (" .. self.name .. ") notification: " .. (msg.method or "unknown"))
    else
        Logger.debug("MCP (" .. self.name .. ") unhandled message: " .. line:sub(1, 100))
    end
end

function MCPClient:request(method: string, params: any?): any
    self.requestId += 1
    local id = self.requestId
    
    local payload = {
        jsonrpc = "2.0",
        id = id,
        method = method,
        params = params or {}
    }
    
    local json = serde.encode("json", payload)
    
    if not self.child or not self.child.stdin then
        return {error = {code = -32000, message = "Not connected"}}
    end
    
    -- Send
    self.child.stdin:write(json .. "\n")
    
    -- Wait for response (Polled via pendingRequests)
    local response = nil
    local done = false
    
    self.pendingRequests[id] = function(msg)
        response = msg
        done = true
    end
    
    local start = os.clock()
    while not done do
        if os.clock() - start > 10 then -- Timeout
            self.pendingRequests[id] = nil
            return {error = {code = -32000, message = "Timeout"}}
        end
        Task.wait(0.01)
    end
    
    return response.result or response.error
end

function MCPClient:initialize()
    local res = self:request("initialize", {
        protocolVersion = "2024-11-05",
        capabilities = {},
        clientInfo = {name = "copal", version = "0.4.0"}
    })
    
    if res and not res.error then
        self.capabilities = res.capabilities
        -- Send initialized notification
        local notify = serde.encode("json", {
            jsonrpc = "2.0",
            method = "notifications/initialized"
        })
        self.child.stdin:write(notify .. "\n")
        return true
    else
        Logger.error("MCP Initialization failed: " .. (res.error and res.error.message or "Unknown"))
        return false
    end
end

function MCPClient:listTools()
    local res = self:request("tools/list")
    if res and res.tools then
        return res.tools
    end
    return {}
end

function MCPClient:callTool(name: string, args: any)
    local res = self:request("tools/call", {
        name = name,
        arguments = args
    })
    
    if res and res.content then
        -- Combine text content
        local text = ""
        for _, item in ipairs(res.content) do
            if item.type == "text" then
                text = text .. item.text
            end
        end
        return text
    elseif res and res.isError then
         return "Error from tool: " .. (res.content and res.content[1] and res.content[1].text or "Unknown")
    end
    
    return "Tool executed."
end

return MCPClient
