--!strict
local Monitor = require("../lib/Monitor")

local Delegation = {}

Delegation.delegateTaskTool = {
    name = "delegate_task",
    description = "Delegate a subtask to another agent in the swarm. The task will be posted to the swarm blackboard and another agent (or a newly spawned one) can pick it up. Use this when you identify work that would be better handled by a separate agent — for example, if your main task requires a side investigation.",
    parameters = {
        type = "object",
        properties = {
            task = {type = "string", description = "Clear description of the subtask to delegate"},
            priority = {
                type = "string",
                description = "Priority: 'low', 'normal', 'high'. Default: 'normal'",
                enum = {"low", "normal", "high"}
            },
            context = {type = "string", description = "Additional context or files relevant to this subtask"},
            preferred_agent = {type = "string", description = "Optional: specific agent ID to assign to (e.g. 'Agent 3')"}
        },
        required = {"task"}
    },
    execute = function(args)
        if not args.task then return "Error: task description required" end
        local priority = args.priority or "normal"
        local context = args.context or ""
        local preferred = args.preferred_agent or "any"
        
        Monitor.emit("log", "Delegation", 
            "[" .. priority:upper() .. "] New subtask delegated → " .. 
            (preferred ~= "any" and preferred or "any available agent") .. 
            ": " .. args.task
        )
        
        -- The actual routing happens in Swarm.luau via the blackboard
        return "Task delegated with priority " .. priority .. ". " ..
            (preferred ~= "any" and (preferred .. " will be notified.") or "Any available agent will pick it up.") ..
            " Continue with your current work."
    end
}

return Delegation
