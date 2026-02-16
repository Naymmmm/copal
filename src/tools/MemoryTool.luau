--!strict
local Memory = require("../core/Memory")

local MemoryTool = {}

MemoryTool.saveMemory = {
    name = "save_memory",
    description = "Save important facts, preferences, or decisions to long-term memory. Use this to remember things across sessions or for later retrieval.",
    parameters = {
        type = "object",
        properties = {
            content = {type = "string", description = "The fact or information to remember. Be concise but descriptive."},
            tags = {type = "array", items = {type = "string"}, description = "Optional tags for categorization (e.g. ['preference', 'tech-stack'])"}
        },
        required = {"content"}
    },
    execute = function(args)
        if not args.content then return "Error: content required" end
        local success = Memory.get():add(args.content, args.tags)
        if success then
            return "Memory saved."
        else
            return "Failed to save memory (embedding error)."
        end
    end
}

MemoryTool.recallMemory = {
    name = "recall_memory",
    description = "Search your long-term memory for relevant information. Use this when you need context from past work or user preferences.",
    parameters = {
        type = "object",
        properties = {
            query = {type = "string", description = "What are you looking for?"}
        },
        required = {"query"}
    },
    execute = function(args)
        if not args.query then return "Error: query required" end
        
        local results = Memory.get():search(args.query, 5)
        if #results == 0 then
            return "No relevant memories found."
        end
        
        local output = "Relevant Memories:\n"
        for i, res in ipairs(results) do
            local percent = math.floor(res.score * 100)
            output = output .. i .. ". (" .. percent .. "%) " .. res.item.content .. "\n"
        end
        return output
    end
}

return MemoryTool
