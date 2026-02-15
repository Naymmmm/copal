--!strict
local FlowControl = {}

-- extend_iterations Tool
FlowControl.extendIterationsTool = {
    name = "extend_iterations",
    description = "Request more iterations to complete the task. Use this ONLY if you are making good progress but need more steps to finish. Do not use if you are stuck.",
    parameters = {
        type = "object",
        properties = {
            reason = {
                type = "string",
                description = "Explanation of why more time is needed and what will be done next."
            },
            count = {
                type = "integer",
                description = "Number of additional iterations to request (default: 5).",
                default = 5
            }
        },
        required = {"reason"}
    },
    execute = function(args: {reason: string, count: number?})
        local count = args.count or 5
        return "Extended iterations by " .. count .. ". Reason: " .. args.reason
    end
}

return FlowControl
