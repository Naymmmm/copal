--!strict
local net = require("@lune/net")

local WebFetch = {}

WebFetch.fetchTool = {
    name = "web_fetch",
    description = "Fetch content from a URL. By default, returns clean readable markdown via Jina Reader (great for docs, articles, web pages). Set raw=true to get the original HTML/text. For search queries, use the 'web_search' tool instead.",
    parameters = {
        type = "object",
        properties = {
            url = {type = "string", description = "The URL to fetch"},
            headers = {type = "object", description = "Optional HTTP headers to include"},
            raw = {type = "boolean", description = "If true, fetch the raw response instead of markdown (default: false)"}
        },
        required = {"url"}
    },
    execute = function(args)
        if not args.url then return "Error: url required" end

        local useRaw = args.raw == true
        local fetchUrl = args.url

        -- Route through Jina Reader for clean markdown unless raw mode
        if not useRaw then
            -- Guard against double-prefixing
            if not fetchUrl:find("r%.jina%.ai/", 1, true) then
                fetchUrl = "https://r.jina.ai/" .. fetchUrl
            end
        end

        local reqHeaders = {
            ["User-Agent"] = "Copal/0.3.0",
            ["Accept"] = "text/html,application/json,text/plain,*/*",
        }

        -- Merge custom headers
        if args.headers and type(args.headers) == "table" then
            for k, v in pairs(args.headers) do
                reqHeaders[k] = v
            end
        end

        local success, response = pcall(function()
            return net.request({
                url = fetchUrl,
                method = "GET",
                headers = reqHeaders,
            })
        end)

        if not success then
            return "Error: Network request failed: " .. tostring(response)
        end

        if not response.ok then
            return "Error: HTTP " .. response.statusCode .. " " .. response.statusMessage
        end

        local body = response.body

        -- Truncate very large responses to save tokens
        if #body > 16000 then
            body = body:sub(1, 16000) .. "\n\n... (response truncated at 16000 chars, " .. #response.body .. " total)"
        end

        return body
    end
}

return WebFetch
