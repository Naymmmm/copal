--!strict
local Task = require("@lune/task")

local Thinking = {}

-- Shared wake signals: agents check this to see if they've been woken up
local _wakeSignals: {[string]: string?} = {}

Thinking.thinkTool = {
    name = "think",
    description = "A scratchpad for internal reasoning. Use this to plan your approach, analyze information, or work through a problem step-by-step BEFORE taking action. This tool has NO side effects — it simply records your thought and returns it. Using this before complex tasks significantly improves outcomes.",
    parameters = {
        type = "object",
        properties = {
            thought = {type = "string", description = "Your reasoning, analysis, or plan. Be detailed."}
        },
        required = {"thought"}
    },
    execute = function(args)
        if not args.thought then return "Error: thought required" end
        return "Thought recorded. Continue with your plan."
    end
}

Thinking.sleepTool = {
    name = "sleep",
    description = "Pause yourself for a number of seconds. Use this when you are WAITING for another agent to finish their work before you can proceed (e.g. waiting for code to be written before compiling). You can be woken early by another agent using the 'wake' tool. Max 30 seconds.",
    parameters = {
        type = "object",
        properties = {
            seconds = {type = "number", description = "How many seconds to sleep (1-30)."},
            reason = {type = "string", description = "Why you are sleeping (e.g. 'Waiting for Agent 2 to finish writing main.py')."}
        },
        required = {"seconds", "reason"}
    },
    execute = function(args)
        local seconds = math.min(math.max(tonumber(args.seconds) or 5, 1), 30)
        local reason = args.reason or "unspecified"
        local agentId = args._agentId or "unknown" -- injected by Swarm

        _wakeSignals[agentId] = nil -- clear any stale wake signal

        -- Sleep in small increments, checking for wake signals
        local elapsed = 0
        while elapsed < seconds do
            Task.wait(0.5)
            elapsed += 0.5
            if _wakeSignals[agentId] then
                local wakedBy = _wakeSignals[agentId]
                _wakeSignals[agentId] = nil
                return "Woken early after " .. math.floor(elapsed) .. "s by " .. wakedBy .. " (was sleeping for: " .. reason .. "). Proceed with your task."
            end
        end

        return "Slept for " .. seconds .. " seconds (reason: " .. reason .. "). Check if the dependency is ready now."
    end
}

Thinking.wakeTool = {
    name = "wake",
    description = "Wake up a sleeping agent. Use this when you've finished work that another agent is waiting for (e.g. you wrote the file they need). The target agent will be interrupted from their sleep and can proceed immediately.",
    parameters = {
        type = "object",
        properties = {
            target = {type = "string", description = "The agent to wake up (e.g. 'Agent 3')."},
            reason = {type = "string", description = "Why you're waking them (e.g. 'main.py is ready to compile')."}
        },
        required = {"target", "reason"}
    },
    execute = function(args)
        if not args.target then return "Error: target required" end
        local reason = args.reason or "no reason given"
        local source = args._agentId or "unknown"

        _wakeSignals[args.target] = source .. " (" .. reason .. ")"
        return "Wake signal sent to " .. args.target .. ". They will resume shortly."
    end
}

return Thinking
