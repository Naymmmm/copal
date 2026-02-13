--!strict
local Task = require("@lune/task")
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local TUI = require("../ui/TUI")
local process = require("@lune/process")
local Monitor = require("../lib/Monitor")
local LLMClient = require("../models/LLMClient")
local Registry = require("../tools/Registry")
local serde = require("@lune/serde")

local Swarm = {}
Swarm.__index = Swarm

function Swarm.new(size: number?, model: string?)
    local self = setmetatable({}, Swarm)
    self._size = size or 5
    self._model = model or Config.getActive().models.low
    self._results = {}
    return self
end

function Swarm:execute(subTasks: {string})
    Logger.info("Swarm activating with " .. #subTasks .. " tasks using model: " .. self._model)
    local results = {}
    local pending = #subTasks

    local securityLevel = Config.security_level or "restricted"
    local cwd = process.cwd

    -- Shared Blackboard for Inter-Agent Communication
    local swarmBlackboard = {}
    
    -- State for Dashboard
    local swarmState = {
        mode = "SWARM MODE",
        activeAgents = #subTasks,
        completedTasks = 0,
        totalTasks = #subTasks,
        agents = {}
    }
    
    -- Initialize Agent State
    for i=1, #subTasks do
        table.insert(swarmState.agents, {id = "Agent " .. i, status = "Idle", iterations = 0})
    end
    
    -- Control Flags
    local isPaused = false
    
    -- Start Input Loop
    -- Note: startInputLoop spawns a thread. We need to be careful not to spawn multiple if Swarm is reused.
    -- Ideally TUI handles this singleton nature.
    TUI.startInputLoop(function(line)
        local cmd = line:match("^(%S+)")
        local args = line:match("^%S+%s+(.*)")
        
        if cmd == "/pause" then
            isPaused = true
            Monitor.log("System", "Swarm PAUSED. Type /resume to continue.")
        elseif cmd == "/resume" then
            isPaused = false
            Monitor.log("System", "Swarm RESUMED.")
        elseif cmd == "/status" then
            TUI.drawDashboard(swarmState)
        elseif cmd == "/info" and args then
            table.insert(swarmBlackboard, {
                source = "User",
                content = args
            })
            Monitor.log("System", "User injected info: " .. args)
        elseif cmd == "/help" then
             Monitor.log("System", "Commands: /pause, /resume, /info <msg>, /status")
        end
    end)
    
    -- Get tools for the agents
    local toolDefs = Registry.getAllDefinitions()
    
    for i, subTask in ipairs(subTasks) do
        local agentId = "Agent " .. i
        
        Task.spawn(function()
            -- Update Status
            swarmState.agents[i].status = "Starting"
            Monitor.log(agentId, "Starting task: " .. subTask)
            
            local systemPrompt = "You are " .. agentId .. ", a specialized worker agent part of a Swarm of " .. self._size .. " agents.\n" ..
[[You have access to the following tools:
- read_file: Read a file from the system.
- write_file: Write text to a file.
- list_files: List files in a directory.
- run_command: Execute a shell command.
- ripgrep: Search for patterns in files.
- broadcast: Send a message to all other agents (use this to ask for help or share results).
- ask_user: Ask the user a question if you need more information.

CONTEXT:
Current Working Directory: ]] .. cwd .. [[
Security Level: ]] .. securityLevel .. [[

RULES:
1. You are ]] .. agentId .. [[.
2. You executed in a secure local environment. File operations are permitted.
3. Use 'broadcast' to collaborate. If you are stuck, ask other agents.
4. Be concise.
5. DO NOT write code blocks. Call the tools directly using the tool usage format.
]]

            if securityLevel == "restricted" then
                systemPrompt = systemPrompt .. "6. You are in RESTRICTED mode. operate ONLY within the Current Working Directory. Do not try to access parent directories.\n"
            else
                systemPrompt = systemPrompt .. "6. You are in FULL ACCESS mode. You may access any file and run any command necessary.\n"
            end

            local messages = {
                {role = "system", content = systemPrompt},
                {role = "user", content = subTask}
            }
            
            local finalOutput = nil
            local iterations = 0
            local maxIterations = 10 
            local lastReadBroadcastIndex = 0
            
            while iterations < maxIterations do
                -- PAUSE CHECK
                while isPaused do
                    Task.wait(1)
                end
                
                iterations += 1
                swarmState.agents[i].iterations = iterations
                swarmState.agents[i].status = "Checking Mail"
                
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
                
                swarmState.agents[i].status = "Thinking"
                Monitor.thought(agentId, "Thinking... (Iter " .. iterations .. ")")
                
                local output, toolCalls = LLMClient.completion(messages, self._model, toolDefs, "auto")
                
                if not output and not toolCalls then
                    swarmState.agents[i].status = "Error (Network)"
                    Monitor.log(agentId, "Error: Failed to get response from LLM (Network/Provider Error).")
                    finalOutput = "Error: LLM Request Failed."
                    break
                end

                if toolCalls and #toolCalls > 0 then
                    swarmState.agents[i].status = "Tool Use"
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
                                    -- SECURITY & APPROVAL CHECK
                                    local approved = true
                                    
                                    if securityLevel == "restricted" and toolName == "run_command" then
                                        swarmState.agents[i].status = "Waiting Approval"
                                        Monitor.log(agentId, "Requesting approval for command: " .. (args.command or "unknown"))
                                        -- We need to ask TUI. Since this is async/spawned, TUI access might overlap.
                                        -- TUI.confirm blocks stdin. 
                                        -- WARNING: If multiple agents ask at once, this is messy.
                                        -- For the "tenfold TUI", we'd need a request queue.
                                        -- For now, let's just block. The user is single-threaded.
                                        -- We should output clearly who is asking.
                                        
                                        local question = "\n[SECURITY WARNING] " .. agentId .. " wants to run: " .. (args.command or "") .. " " .. table.concat(args.args or {}, " ") .. "\nAllow?"
                                        approved = TUI.confirm(question)
                                        
                                        if not approved then
                                            Monitor.log(agentId, "Command denied by user.")
                                            toolResult = "Error: User denied permission to run this command."
                                        end
                                        swarmState.agents[i].status = "Resuming"
                                    end
                                    
                                    if approved then
                                        swarmState.agents[i].status = "Executing " .. toolName
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
                    swarmState.agents[i].status = "Done"
                    finalOutput = output
                    break
                end
            end
            
            if not finalOutput then
                finalOutput = "Failed: Max iterations reached."
                swarmState.agents[i].status = "Failed"
                Monitor.log(agentId, "Failed: Max iterations reached.")
            else
                swarmState.agents[i].status = "Success"
                Monitor.completion(agentId, finalOutput)
            end
            
            swarmState.completedTasks += 1

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
