--!strict

local Thinking = {}

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
        -- No-op: just echo back the thought so it stays in context
        return "Thought recorded. Continue with your plan."
    end
}

return Thinking
