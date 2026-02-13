--!strict
local TUI = require("../ui/TUI")

local Interaction = {}

local askUserTool = {
    name = "ask_user",
    description = "Ask the user a question if you need more information or clarification. Use this sparingly but whenever you are stuck or need user input.",
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
        return TUI.prompt(args.question)
    end
}

Interaction.askUserTool = askUserTool

return Interaction
