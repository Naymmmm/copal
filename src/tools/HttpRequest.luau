--!strict
local net = require("@lune/net")
local serde = require("@lune/serde")

local HttpRequest = {}

HttpRequest.requestTool = {
    name = "http_request",
    description = "Make an HTTP request with any method (GET, POST, PUT, PATCH, DELETE). Supports JSON body, custom headers, and returns status + body. Use for API testing, webhooks, or any HTTP interaction beyond simple page fetching.",
    parameters = {
        type = "object",
        properties = {
            url = { type = "string", description = "The URL to request" },
            method = { type = "string", description = "HTTP method: GET, POST, PUT, PATCH, DELETE (default: GET)" },
            body = { type = "string", description = "Request body (string). For JSON, pass a JSON string." },
            json = { type = "object", description = "JSON body (will be serialized and Content-Type set automatically)" },
            headers = { type = "object", description = "Custom HTTP headers" },
        },
        required = { "url" },
    },
    execute = function(args)
        if not args.url then return "Error: url required" end

        local method = (args.method or "GET"):upper()
        local validMethods = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true, HEAD = true, OPTIONS = true }
        if not validMethods[method] then
            return "Error: invalid method '" .. method .. "'. Use GET, POST, PUT, PATCH, DELETE, HEAD, or OPTIONS."
        end

        local reqHeaders: { [string]: string } = {
            ["User-Agent"] = "Copal/0.3.0",
            ["Accept"] = "*/*",
        }

        -- Merge custom headers
        if args.headers and type(args.headers) == "table" then
            for k, v in pairs(args.headers) do
                reqHeaders[k] = tostring(v)
            end
        end

        local body: string? = nil

        -- JSON body takes priority
        if args.json then
            local ok, encoded = pcall(function()
                return serde.encode("json", args.json)
            end)
            if ok then
                body = encoded
                reqHeaders["Content-Type"] = reqHeaders["Content-Type"] or "application/json"
            else
                return "Error: failed to encode JSON body: " .. tostring(encoded)
            end
        elseif args.body then
            body = args.body
        end

        local success, response = pcall(function()
            return net.request({
                url = args.url,
                method = method,
                headers = reqHeaders,
                body = body,
            })
        end)

        if not success then
            return "Error: Request failed: " .. tostring(response)
        end

        -- Build response output
        local output = {}
        table.insert(output, "HTTP " .. response.statusCode .. " " .. (response.statusMessage or ""))

        -- Show response headers summary
        if response.headers then
            local ct = response.headers["content-type"]
            if ct then
                table.insert(output, "Content-Type: " .. ct)
            end
        end

        table.insert(output, "")

        -- Body
        local respBody = response.body or ""
        if #respBody > 16000 then
            respBody = respBody:sub(1, 16000) .. "\n\n... (response truncated at 16000 chars, " .. #response.body .. " total)"
        end
        table.insert(output, respBody)

        return table.concat(output, "\n")
    end,
}

return HttpRequest
