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
    local approvalLock = false
    
    local function acquireApprovalLock()
        while approvalLock do
            Task.wait(0.2)
        end
        approvalLock = true
        isPaused = true
        Task.wait(0.3)
    end
    
    local function releaseApprovalLock()
        approvalLock = false
        isPaused = false
    end
    
    -- Register swarm-specific slash commands
    TUI.registerCommand({
        name = "pause",
        description = "Pause all agents",
        usage = "pause",
        handler = function()
            isPaused = true
            Monitor.log("System", "Swarm PAUSED. Type /resume to continue.")
        end,
    })
    
    TUI.registerCommand({
        name = "resume",
        description = "Resume paused agents",
        usage = "resume",
        handler = function()
            isPaused = false
            Monitor.log("System", "Swarm RESUMED.")
        end,
    })
    
    TUI.registerCommand({
        name = "status",
        description = "Show agent dashboard",
        usage = "status",
        handler = function()
            TUI.drawDashboard(swarmState)
        end,
    })
    
    TUI.registerCommand({
        name = "info",
        description = "Inject info into agent context",
        usage = "info <message>",
        handler = function(args: string?)
            if args and #args > 0 then
                table.insert(swarmBlackboard, {
                    source = "User",
                    content = args
                })
                Monitor.log("System", "Injected: " .. args)
            else
                Monitor.log("System", "Usage: /info <message>")
            end
        end,
    })
    
    -- Start the input loop (dispatches slash commands automatically)
    TUI.startInputLoop(function(line)
        -- Non-command input during swarm execution is ignored
        -- (or could be used to feed info to agents)
    end)
    
    -- Get tools for the agents
    local toolDefs = Registry.getAllDefinitions()
    
    -- ════════════════════════════════════════════════
    --  PHASE 0: Build Team Roster
    -- ════════════════════════════════════════════════
    local teamRoster = "\nTEAM ROSTER (who is working on what):\n"
    for j, task in ipairs(subTasks) do
        teamRoster = teamRoster .. "- Agent " .. j .. ": " .. task .. "\n"
    end
    teamRoster = teamRoster .. "\nUse 'whisper' to message a specific agent by name (e.g. 'Agent 2').\n"
    teamRoster = teamRoster .. "Use 'broadcast' to share findings with the entire team.\n"
    teamRoster = teamRoster .. "Coordinate to avoid duplicate work. If another agent's task overlaps with yours, whisper them.\n"
    
    -- ════════════════════════════════════════════════
    --  PHASE 1: Coordination (agents announce plans)
    -- ════════════════════════════════════════════════
    if #subTasks > 1 then
        Monitor.log("Swarm", "Coordination phase: agents announcing plans...")
        
        local plansPending = #subTasks
        
        for i, subTask in ipairs(subTasks) do
            local agentId = "Agent " .. i
            
            Task.spawn(function()
                swarmState.agents[i].status = "Planning"
                
                local planPrompt = {
                    {role = "system", content = "You are " .. agentId .. ". You are about to start working on a task as part of a team." .. teamRoster .. "\nYour assigned task: " .. subTask .. "\n\nIn 1-2 sentences, describe your plan and what files/resources you expect to touch. Be specific so other agents can coordinate with you. Reply with ONLY your plan, no extra text."},
                    {role = "user", content = "Announce your plan to the team."}
                }
                
                local plan, _ = LLMClient.completion(planPrompt, self._model, nil, nil)
                
                if plan and #plan > 0 then
                    table.insert(swarmBlackboard, {
                        type = "plan",
                        source = agentId,
                        content = plan
                    })
                    Monitor.log(agentId, "Plan: " .. plan)
                else
                    table.insert(swarmBlackboard, {
                        type = "plan",
                        source = agentId,
                        content = "(no plan provided)"
                    })
                end
                
                plansPending -= 1
            end)
        end
        
        -- Wait for all agents to announce their plans
        while plansPending > 0 do
            Task.wait(0.1)
        end
        
        Monitor.log("Swarm", "All agents have announced plans. Starting execution...")
    end
    
    -- ════════════════════════════════════════════════
    --  PHASE 2: Execution (agents work on their tasks)
    -- ════════════════════════════════════════════════
    for i, subTask in ipairs(subTasks) do
        local agentId = "Agent " .. i
        
        Task.spawn(function()
            swarmState.agents[i].status = "Starting"
            Monitor.log(agentId, "Starting task: " .. subTask)
            
            local osName = process.os
            local archName = process.arch
            
            local systemPrompt = "You are " .. agentId .. ", a specialized worker agent part of a Swarm of " .. self._size .. " agents.\n" ..
[[You have access to the following tools:

FILE TOOLS:
- read_file: Read entire file contents.
- read_file_lines: Read specific line range (more efficient for big files).
- write_file: Write/overwrite a file entirely.
- patch_file: Find-and-replace within a file (safer for shared files).
- delete_file: Delete a file.
- create_directory: Create a directory (with parents).
- list_files: List files in a directory.

TERMINAL & SEARCH:
- run_command: Execute a shell command.
- ripgrep: Fast pattern search across files.
- web_fetch: HTTP GET a URL (docs, references, raw files).

COMMUNICATION:
- broadcast: Send a message to ALL agents.
- whisper: Private message to ONE agent (e.g. 'Agent 2').
- request_help: Signal you're stuck and need collaboration.
- report_progress: Share status and files you've touched.
- ask_user: Ask the user a question.

REASONING, FLOW CONTROL & DELEGATION:
- think: Internal scratchpad — plan before acting (NO side effects).
- sleep: Pause yourself for N seconds (1-30). Use when waiting for another agent to finish (e.g. waiting for code before compiling).
- wake: Wake a sleeping agent by name (e.g. 'Agent 3'). Use when you finish work they depend on.
- delegate_task: Spawn a subtask for another agent to handle.

CONTEXT:
Operating System: ]] .. osName .. [[
Architecture: ]] .. archName .. [[
Current Working Directory: ]] .. cwd .. [[
Security Level: ]] .. securityLevel .. [[
]] .. teamRoster .. [[

RULES:
1. You are ]] .. agentId .. [[.
2. ALWAYS use 'think' first to plan your approach before taking action.
3. Use commands appropriate for the OS (e.g. PowerShell on Windows, bash on Linux). NEVER use 'sudo' or 'apt' on Windows.
4. Use 'patch_file' instead of 'write_file' when editing existing files.
5. Use 'report_progress' after completing significant work to share what files you touched.
6. If stuck, use 'request_help'. If a subtask would be better done separately, use 'delegate_task'.
7. Be concise. Call tools directly — do NOT write code blocks.
8. CHECK THE TEAM ROSTER. If another agent is working on a related task, coordinate with them via 'whisper'.
]]

            if securityLevel == "restricted" then
                systemPrompt = systemPrompt .. "9. You are in RESTRICTED mode. Operate ONLY within the Current Working Directory. Do not try to access parent directories.\n"
            else
                systemPrompt = systemPrompt .. "9. You are in FULL ACCESS mode. You may access any file and run any command necessary.\n"
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
                while isPaused or approvalLock do
                    swarmState.agents[i].status = "Paused"
                    Task.wait(0.5)
                end
                
                iterations += 1
                swarmState.agents[i].iterations = iterations
                swarmState.agents[i].status = "Checking Mail"
                
                -- Sync Blackboard (typed message routing)
                if #swarmBlackboard > lastReadBroadcastIndex then
                    for j = lastReadBroadcastIndex + 1, #swarmBlackboard do
                        local msg = swarmBlackboard[j]
                        if msg.source ~= agentId then
                            -- Skip whispers/delegations not addressed to this agent
                            if msg.type == "whisper" and msg.target ~= agentId then
                                continue
                            end
                            if msg.type == "delegation" and msg.target and msg.target ~= agentId then
                                continue
                            end
                            
                            local prefix = "[Broadcast from " .. msg.source .. "]"
                            if msg.type == "whisper" then
                                prefix = "[Whisper from " .. msg.source .. "]"
                            elseif msg.type == "help" then
                                prefix = "[Help Request from " .. msg.source .. "]"
                            elseif msg.type == "progress" then
                                prefix = "[Progress from " .. msg.source .. "]"
                            elseif msg.type == "delegation" then
                                prefix = "[Delegated Task from " .. msg.source .. "]"
                            elseif msg.type == "plan" then
                                prefix = "[Plan from " .. msg.source .. "]"
                            end
                            
                            table.insert(messages, {
                                role = "user",
                                content = prefix .. ": " .. msg.content
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
                    Monitor.log(agentId, "Error: LLM request failed.")
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
                                local valid, invalidReason = Registry.validate(toolName, args)
                                
                                if valid then
                                    local approved = true
                                    
                                    -- SECURITY: run_command approval in restricted mode
                                    if securityLevel == "restricted" and toolName == "run_command" then
                                        swarmState.agents[i].status = "Waiting Approval"
                                        acquireApprovalLock()
                                        
                                        local cmdStr = (args.command or "unknown")
                                        if args.args and #args.args > 0 then
                                            cmdStr = cmdStr .. " " .. table.concat(args.args, " ")
                                        end
                                        
                                        approved = TUI.confirm(agentId .. " wants to run:\n  > " .. cmdStr)
                                        
                                        if not approved then
                                            Monitor.log(agentId, "Command denied.")
                                            toolResult = "Error: User denied permission."
                                        end
                                        
                                        releaseApprovalLock()
                                        swarmState.agents[i].status = "Resuming"
                                    end
                                    
                                    -- ask_user locks stdin too
                                    if toolName == "ask_user" then
                                        swarmState.agents[i].status = "Asking User"
                                        acquireApprovalLock()
                                        
                                        local answer = TUI.askUser(agentId .. " asks:\n  " .. (args.question or ""))
                                        toolResult = answer
                                        
                                        releaseApprovalLock()
                                        swarmState.agents[i].status = "Resuming"
                                        approved = false
                                    end
                                    
                                    if approved then
                                        -- Inject agent identity for sleep/wake tools
                                        if toolName == "sleep" or toolName == "wake" then
                                            args._agentId = agentId
                                        end
                                        
                                        if toolName == "sleep" then
                                            swarmState.agents[i].status = "Sleeping"
                                            Monitor.log(agentId, "Sleeping: " .. (args.reason or ""))
                                        elseif toolName == "wake" then
                                            Monitor.log(agentId, "Waking " .. (args.target or "?") .. ": " .. (args.reason or ""))
                                        else
                                            swarmState.agents[i].status = "Executing " .. toolName
                                        end
                                        
                                        Monitor.log(agentId, "Executing " .. toolName)
                                        toolResult = toolDef.execute(args)
                                        
                                        -- Route communication & delegation to blackboard
                                        if toolName == "broadcast" and args.message then
                                            table.insert(swarmBlackboard, {
                                                type = "broadcast",
                                                source = agentId,
                                                content = args.message,
                                                priority = args.priority or "info"
                                            })
                                        elseif toolName == "whisper" and args.message then
                                            table.insert(swarmBlackboard, {
                                                type = "whisper",
                                                source = agentId,
                                                target = args.target,
                                                content = args.message
                                            })
                                        elseif toolName == "request_help" and args.topic then
                                            table.insert(swarmBlackboard, {
                                                type = "help",
                                                source = agentId,
                                                content = "HELP [" .. (args.expertise_needed or "any") .. "]: " .. args.topic .. " — " .. args.details
                                            })
                                        elseif toolName == "report_progress" and args.summary then
                                            table.insert(swarmBlackboard, {
                                                type = "progress",
                                                source = agentId,
                                                content = "[" .. (args.status or "update"):upper() .. "] " .. args.summary .. (args.files_modified and (" | Files: " .. args.files_modified) or "")
                                            })
                                        elseif toolName == "delegate_task" and args.task then
                                            table.insert(swarmBlackboard, {
                                                type = "delegation",
                                                source = agentId,
                                                target = args.preferred_agent or nil,
                                                content = "[" .. (args.priority or "normal"):upper() .. " TASK] " .. args.task .. (args.context and ("\nContext: " .. args.context) or "")
                                            })
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
                Monitor.log(agentId, "Max iterations reached.")
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
