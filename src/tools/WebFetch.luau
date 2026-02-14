--!strict
local net = require("@lune/net")

local WebFetch = {}

WebFetch.fetchTool = {
    name = "web_fetch",
    description = "Fetch content from a URL via HTTP GET. Returns the response body as text. Useful for reading documentation, API references, or raw files from the web. For search queries, use the 'search' tool instead.",
    parameters = {
        type = "object",
        properties = {
            url = {type = "string", description = "The URL to fetch"},
            headers = {type = "object", description = "Optional HTTP headers to include"}
        },
        required = {"url"}
    },
    execute = function(args)
        if not args.url then return "Error: url required" end
        
        local reqHeaders = {
            ["User-Agent"] = "Copal/0.2.0",
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
                url = args.url,
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
        if #body > 8000 then
            body = body:sub(1, 8000) .. "\n\n... (response truncated at 8000 chars, " .. #response.body .. " total)"
        end
        
        return body
    end
}

return WebFetch
