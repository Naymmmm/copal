--!strict
local net = require("@lune/net")
local serde = require("@lune/serde")
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local Auth = require("../core/Auth")

local LLMClient = {}

type FunctionDef = {
    name: string,
    description: string,
    parameters: any
}

type Tool = {
    type: "function",
    ["function"]: FunctionDef
}

type Message = {
    role: "system" | "user" | "assistant" | "tool",
    content: string?,
    tool_calls: {any}?,
    tool_call_id: string?
}

-- Internal helper for retrying requests
local function requestWithRetry(provider: any, body: string)
    local maxRetries = 3
    local attempt = 0
    local lastError = "Unknown Error"
    
    while attempt < maxRetries do
        attempt += 1
        
        local success, response = pcall(function()
            return net.request({
                url = provider.url .. "/chat/completions",
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. provider.key,
                },
                body = body,
            })
        end)

        if success and response.ok then
            local decodeSuccess, decoded = pcall(function() return serde.decode("json", response.body) end)
            if decodeSuccess then
                if decoded.choices and #decoded.choices > 0 then
                    return decoded
                end
                lastError = "Response missing choices field"
            else
                lastError = "Failed to parse JSON response"
            end
        elseif success then
            lastError = "HTTP " .. response.statusCode .. ": " .. response.statusMessage
            Logger.warn("Attempt " .. attempt .. " failed: " .. lastError)
            
            if response.statusCode == 429 or response.statusCode >= 500 then
                 local waitTime = math.pow(2, attempt)
                 Logger.info("Retrying in " .. waitTime .. "s...")
                 require("@lune/task").wait(waitTime)
            else
                 break -- Fatal error
            end
        else
            lastError = "Network Request Failed: " .. tostring(response)
            Logger.warn("Attempt " .. attempt .. " failed: " .. lastError)
            require("@lune/task").wait(1)
        end
    end

    Logger.error("LLM Request failed after " .. maxRetries .. " attempts. Last error: " .. lastError)
    return nil
end

function LLMClient.completion(messages: {Message}, model: string, tools: {Tool}?, toolChoice: any?): (string?, {any}?)
    local provider = Config.getActive()
    
    if not provider.key or #provider.key == 0 then
        Logger.error("No API Key found for provider: " .. Config.active_provider)
        return nil, nil
    end

    local payload = {
        model = model,
        messages = messages,
        temperature = 0.7,
        tools = tools,
        tool_choice = (tools and #tools > 0) and toolChoice or nil
    }

    local body = serde.encode("json", payload)

    -- Call internal request with retries
    local data = requestWithRetry(provider, body)
    if not data then return nil, nil end

    if data.choices and #data.choices > 0 then
        local message = data.choices[1].message
        local content = message.content
        local toolCalls = message.tool_calls
        
        -- Fallback: If no native tool calls, check for text-based patterns
        -- Pattern: <|tool_call_start|>[func(args)]<|tool_call_end|>
        if not toolCalls and content and content:find("<|tool_call_start|>") then
            toolCalls = {}
            local cleanContent = content
            
            for match in content:gmatch("<%|tool_call_start%|>(.-)<%|tool_call_end%|>") do
                local inner = match:match("^%[(.*)%]$")
                if inner then
                    local nameOffset = inner:find("%(")
                    if nameOffset then
                        local name = inner:sub(1, nameOffset - 1)
                        local argsRaw = inner:sub(nameOffset + 1, -2)
                        
                        local jsonParts = {}
                        for k, v in argsRaw:gmatch("(%w+)='(.-)'") do
                            table.insert(jsonParts, '"' .. k .. '": "' .. v .. '"')
                        end
                        for k, v in argsRaw:gmatch('(%w+)="(.-)"') do
                            table.insert(jsonParts, '"' .. k .. '": "' .. v .. '"')
                        end
                        
                        local jsonStr = "{" .. table.concat(jsonParts, ", ") .. "}"
                        local callId = "call_" .. math.random(10000, 99999)
                        
                        table.insert(toolCalls, {
                            id = callId,
                            type = "function",
                            ["function"] = {
                                name = name,
                                arguments = jsonStr
                            }
                        })
                        
                        cleanContent = cleanContent:gsub("<%|tool_call_start%|>" .. match:gsub("([^%w])", "%%%1") .. "<%|tool_call_end%|>", "")
                    end
                end
            end
            
            if #toolCalls > 0 then
                Logger.info("Parsed " .. #toolCalls .. " text-based tool calls.")
                content = cleanContent
            else
                toolCalls = nil 
            end

            -- If still no tool calls, try to parse JSON blocks
            if not toolCalls and content and (content:find("{") and content:find("}")) then
                 local jsonBlock = content:match("({.*})")
                 if not jsonBlock then
                     jsonBlock = content:match("```json%s*({.*})%s*```")
                 end
                 
                 if jsonBlock then
                     local success, parsed = pcall(function() return serde.decode("json", jsonBlock) end)
                     if success and parsed.name and parsed.arguments then
                         if not toolCalls then toolCalls = {} end
                         
                         local argsStr = ""
                         if type(parsed.arguments) == "table" then
                             argsStr = serde.encode("json", parsed.arguments)
                         else
                             argsStr = tostring(parsed.arguments)
                         end
                         
                         table.insert(toolCalls, {
                            id = "call_fallback_json_" .. math.random(10000, 99999),
                            type = "function",
                            ["function"] = {
                                name = parsed.name,
                                arguments = argsStr
                            }
                        })
                        Logger.info("Parsed JSON-based tool call.")
                     end
                 end
            end
            
            -- If still no blocks, parse simple code blocks
            if not toolCalls and content and (content:find("```python") or content:find("```lua") or content:find("```")) then
                local filename, fileContent = content:match("write_file%(['\"](.-)['\"],%s*['\"](.-)['\"]%)")
                if filename and fileContent then
                     if not toolCalls then toolCalls = {} end
                     local jsonStr = "{\"path\": \"" .. filename .. "\", \"content\": \"" .. fileContent .. "\"}"
                     table.insert(toolCalls, {
                        id = "call_fallback_" .. math.random(10000, 99999),
                        type = "function",
                        ["function"] = {
                            name = "write_file",
                            arguments = jsonStr
                        }
                    })
                    Logger.info("Parsed write_file from code block.")
                end
                
                local cmd = content:match("run_command%(['\"](.-)['\"]%)")
                if cmd then
                     if not toolCalls then toolCalls = {} end
                     local jsonStr = "{\"command\": \"" .. cmd .. "\"}"
                     table.insert(toolCalls, {
                        id = "call_fallback_" .. math.random(10000, 99999),
                        type = "function",
                        ["function"] = {
                            name = "run_command",
                            arguments = jsonStr
                        }
                    })
                    Logger.info("Parsed run_command from code block.")
                end
            end

        end

        return content, toolCalls
    end

    return nil, nil
end

return LLMClient
