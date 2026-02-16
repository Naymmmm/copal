--!strict
local net = require("@lune/net")
local serde = require("@lune/serde")
local Config = require("../lib/Config")
local LLMClient = require("../models/LLMClient")
local Logger = require("../lib/Logger")

local Search = {}

Search.searchTool = {
    name = "web_search",
    description = "Search the web for up-to-date information. Returns titles, URLs, and content summaries. Use this for current events, documentation, or facts not in training data.",
    parameters = {
        type = "object",
        properties = {
            query = {type = "string", description = "The search query. Be specific."},
            max_results = {type = "number", description = "Maximum number of results (default: 5)"}
        },
        required = {"query"}
    },
    execute = function(args)
        if not args.query then return "Error: query required" end

        local maxResults = args.max_results or 5

        Logger.info("Searching web for: " .. args.query)

        -- Try Jina Search API first
        local jinaOk, jinaResult = pcall(function()
            local encodedQuery = net.urlEncode(args.query)
            local url = "https://s.jina.ai/" .. encodedQuery

            local response = net.request({
                url = url,
                method = "GET",
                headers = {
                    ["Accept"] = "application/json",
                    ["User-Agent"] = "Copal/0.3.0",
                },
            })

            if not response.ok then
                error("HTTP " .. response.statusCode)
            end

            return response.body
        end)

        if jinaOk and jinaResult then
            -- Try to parse as JSON
            local parseOk, parsed = pcall(function()
                return serde.decode("json", jinaResult)
            end)

            if parseOk and parsed and parsed.data then
                local output = {}
                local count = 0

                for _, item in ipairs(parsed.data) do
                    if count >= maxResults then break end
                    count += 1

                    local title = item.title or "Untitled"
                    local itemUrl = item.url or ""
                    local content = item.content or item.description or ""

                    -- Truncate individual result content
                    if #content > 500 then
                        content = content:sub(1, 500) .. "..."
                    end

                    table.insert(output, "### " .. count .. ". " .. title)
                    if itemUrl ~= "" then
                        table.insert(output, "URL: " .. itemUrl)
                    end
                    table.insert(output, content)
                    table.insert(output, "")
                end

                if #output > 0 then
                    return "Search Results for: " .. args.query .. "\n\n" .. table.concat(output, "\n")
                end
            end

            -- If JSON parsing failed, the response might be plain text/markdown
            if #jinaResult > 0 then
                local body = jinaResult
                if #body > 8000 then
                    body = body:sub(1, 8000) .. "\n\n... (truncated)"
                end
                return "Search Results for: " .. args.query .. "\n\n" .. body
            end
        end

        -- Fallback: use LLM-based search model if configured
        Logger.info("Jina search failed, falling back to search model...")

        local provider = Config.getActive()
        local searchModel = provider.models.search

        if not searchModel then
            if jinaOk then
                return "Search returned no results for: " .. args.query
            end
            return "Error: Search failed and no fallback 'search' model configured for provider (" .. Config.active_provider .. ")."
        end

        local messages = {
            { role = "user", content = args.query }
        }

        local content, _ = LLMClient.completion(messages, searchModel, nil, nil)

        if content then
            return "Search Results:\n" .. content
        else
            return "Error: Search request failed or returned no content."
        end
    end
}

return Search
