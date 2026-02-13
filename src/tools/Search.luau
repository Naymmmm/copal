--!strict
local LLMClient = require("../models/LLMClient")
local Config = require("../lib/Config")
local Monitor = require("../lib/Monitor")

local Search = {}

-- Define the tool schema for the LLM
Search.definition = {
    name = "search",
    description = "Search the web for up-to-date information.",
    parameters = {
        type = "object",
        properties = {
            query = {
                type = "string",
                description = "The search query to execute."
            }
        },
        required = {"query"}
    }
}

-- Execute the search
function Search.execute(args: {query: string}): string
    local query = args.query
    local provider = Config.getActive()
    local searchModel = provider.models.search or "perplexity/sonar-reasoning" -- Fallback

    Monitor.log("Tool:Search", "Searching via " .. searchModel .. ": " .. query)

    local messages = {
        {
            role = "system",
            content = "You are a search engine assistant. You have access to the internet. Search for the user's query and provide a concise, factual summary of the results."
        },
        {
            role = "user",
            content = query
        }
    }

    local result, callError = LLMClient.completion(messages, searchModel, nil, nil)
    
    if not result then
        return "Error performing search: " .. (tostring(callError) or "Unknown error")
    end

    return "Search Results:\n" .. result
end

return Search
