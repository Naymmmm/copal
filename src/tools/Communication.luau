--!strict
local Monitor = require("../lib/Monitor")

local Communication = {}

Communication.broadcastTool = {
    name = "broadcast",
    description = "Broadcast a message to all other agents in the swarm.",
    parameters = {
        type = "object",
        properties = {
            message = {type = "string", description = "The message to broadcast"}
        },
        required = {"message"}
    },
    execute = function(args)
        if not args.message then return "Error: message required" end
        -- Monitor will handle the actual event emission which Swarm listens to
        return "Message broadcasted: " .. args.message
    end
}

return Communication
