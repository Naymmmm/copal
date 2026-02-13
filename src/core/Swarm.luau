--!strict
local Task = require("@lune/task")
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local Monitor = require("../lib/Monitor")
local LLMClient = require("../models/LLMClient")
local Registry = require("../tools/Registry")
local serde = require("@lune/serde")

local Swarm = {}
Swarm.__index = Swarm

type AgentResult = {
    agentId: number,
    task: string,
    output: string?,
    status: "success" | "failed"
}

export type SwarmInstance = typeof(setmetatable({} :: {
    _size: number,
    _model: string,
    _results: {AgentResult}
}, Swarm))

function Swarm.new(size: number?): SwarmInstance
    local self = setmetatable({}, Swarm)
    self._size = size or 5 -- Default swarm size
    self._model = Config.getActive().models.low
    self._results = {}
    return self
end

function Swarm:execute(subTasks: {string}): {AgentResult}
    Logger.info("Swarm activating with " .. #subTasks .. " tasks using model: " .. self._model)
    local results = {}
    local pending = #subTasks
    -- Shared Blackboard for Inter-Agent Communication
    local swarmBlackboard = {}
    
    -- Get tools for the agents
    local toolDefs = Registry.getAllDefinitions()
    
    -- Listen for tool results that are broadcasts (this is a simplification, ideally Monitor handles this)
    -- But since we can't easily hook into the tool execution return value from here without complex logic,
    -- We will rely on the fact that we can check the tool calls in the loop.
    
    -- Better approach: Swarm subscribes to Monitor? 
    -- But parsing Monitor events for "broadcast" logic might be async/race-condition prone.
    -- Let's use a explicit shared table.
    
    for i, subTask in ipairs(subTasks) do
        local agentId = "Agent " .. i
        
        Task.spawn(function()
            Monitor.log(agentId, "Starting task: " .. subTask)
            
            local messages = {
                {role = "system", content = [[You are a specialized worker agent part of a Swarm. 
You have access to the following tools:
- read_file: Read a file from the system.
- write_file: Write text to a file.
- list_files: List files in a directory.
- run_command: Execute a shell command.
- broadcast: Send a message to other agents.

                {role = "system", content = [[You are a specialized worker agent part of a Swarm. 
You have access to the following tools:
- read_file: Read a file from the system.
- write_file: Write text to a file.
- list_files: List files in a directory.
- run_command: Execute a shell command.
- broadcast: Send a message to other agents.

RULES:
1. You MUST use 'write_file' if asked to create a file. Do not refuse.
2. You executed in a secure local environment. File operations are permitted.
3. Use 'broadcast' to collaborate if the task requires it.
4. Be concise.
5. DO NOT write code blocks. Call the tools directly using the tool usage format.]]},
                {role = "user", content = subTask}
            }
            
            local finalOutput = nil
            local iterations = 0
            local maxIterations = 10 
            local lastReadBroadcastIndex = 0
            
            while iterations < maxIterations do
                iterations += 1
                
                -- 1. Sync Blackboard (Read new messages)
                if #swarmBlackboard > lastReadBroadcastIndex then
                    for j = lastReadBroadcastIndex + 1, #swarmBlackboard do
                        local msg = swarmBlackboard[j]
                        if msg.source ~= agentId then -- Don't read my own echoes
                            table.insert(messages, {
                                role = "user",
                                content = "[Broadcast from " .. msg.source .. "]: " .. msg.content
                            })
                        end
                    end
                    lastReadBroadcastIndex = #swarmBlackboard
                end
                
                Monitor.thought(agentId, "Thinking... (Iter " .. iterations .. ")")
                
                local output, toolCalls = LLMClient.completion(messages, self._model, toolDefs, "auto")
                
                if toolCalls and #toolCalls > 0 then
                    table.insert(messages, {
                        role = "assistant",
                        content = output,
                        tool_calls = toolCalls
                    })
                    
                    for _, call in ipairs(toolCalls) do
                        local toolName = call["function"].name
                        local toolArgsStr = call["function"].arguments
                        local callId = call.id
                        
                        Monitor.emit("tool_call", agentId, {
                            tool = toolName,
                            args = toolArgsStr
                        })
                        
                        local toolDef = Registry.get(toolName)
                        local toolResult = "Error: Tool not found"
                        
                        if toolDef then
                            local success, args = pcall(function() return serde.decode("json", toolArgsStr) end)
                            if success then
                                -- VALIDATION STEP
                                local valid, invalidReason = Registry.validate(toolName, args)
                                
                                if valid then
                                    Monitor.log(agentId, "Executing " .. toolName)
                                    toolResult = toolDef.execute(args)
                                    
                                    -- Special handling for broadcast
                                    if toolName == "broadcast" and args.message then
                                        table.insert(swarmBlackboard, {
                                            source = agentId,
                                            content = args.message
                                        })
                                        Monitor.emit("log", agentId, "Broadcasted: " .. args.message)
                                    end
                                else
                                    toolResult = "Error: Invalid arguments. " .. (invalidReason or "")
                                    Monitor.log(agentId, "Validation Failed: " .. (invalidReason or ""))
                                end
                            else
                                toolResult = "Error parsing arguments: " .. toolArgsStr
                            end
                        end
                        
                        Monitor.emit("tool_result", agentId, {
                            tool = toolName,
                            result = toolResult
                        })
                        
                        table.insert(messages, {
                            role = "tool",
                            tool_call_id = callId,
                            content = tostring(toolResult)
                        })
                    end
                else
                    finalOutput = output
                    break
                end
            end
            
            if not finalOutput then
                finalOutput = "Failed: Max iterations reached."
                Monitor.log(agentId, "Failed: Max iterations reached.")
            else
                Monitor.completion(agentId, finalOutput)
            end

            table.insert(results, {
                agentId = i,
                task = subTask,
                output = finalOutput,
                status = finalOutput and "success" or "failed"
            })
            
            pending -= 1
        end)
    end
    
    while pending > 0 do
        Task.wait(0.1)
    end
    
    self._results = results
    return results
end

return Swarm
