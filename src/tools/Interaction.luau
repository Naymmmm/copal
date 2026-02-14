--!strict
local TUI = require("../ui/TUI")

local Interaction = {}

local askUserTool = {
    name = "ask_user",
    description = "Ask the user a question if you need more information or clarification. The entire swarm will pause while the user answers. Use this sparingly but whenever you are stuck or need user input.",
    parameters = {
        type = "object",
        properties = {
            question = {
                type = "string",
                description = "The question to ask the user."
            }
        },
        required = {"question"}
    },
    execute = function(args: {question: string})
        -- Note: The actual stdin locking and pause is handled by Swarm.luau
        -- when it detects an ask_user tool call. This execute function is a
        -- fallback for non-swarm usage.
        return TUI.askUser(args.question)
    end
}

Interaction.askUserTool = askUserTool

return Interaction
