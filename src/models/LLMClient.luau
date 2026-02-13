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

    if not success then
        Logger.error("Network request failed. Please check your internet connection or API URL.")
        return nil, nil
    end

    if not response.ok then
        Logger.error("LLM Request failed: " .. response.statusMessage .. " (" .. response.statusCode .. ")")
        Logger.debug("Response body: " .. response.body)
        if response.statusCode == 401 then
            Logger.error("Unauthorized: Invalid API Key.")
        elseif response.statusCode == 404 then
            Logger.error("Not Found: Invalid Model or API URL.")
        end
        return nil, nil
    end

    local decodeSuccess, data = pcall(function() return serde.decode("json", response.body) end)
    if not decodeSuccess then
        Logger.error("Failed to parse response JSON.")
        return nil, nil
    end

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
                -- match e.g.: [write_file(content='Tool use verified', filename='agent_tool_test.txt')]
                -- This parsing is tricky in Luau without regex, but we'll try a basic approach
                -- Removing outer brackets
                local inner = match:match("^%[(.*)%]$")
                if inner then
                    local nameOffset = inner:find("%(")
                    if nameOffset then
                        local name = inner:sub(1, nameOffset - 1)
                        local argsRaw = inner:sub(nameOffset + 1, -2) -- remove last )
                        
                        -- Very naive argument parser: assume keys are simple and values are strings
                        -- Ideally we'd use a real parser, but for this specific model format:
                        local args = {}
                        
                        -- Try to convert python-style kwargs to json valid string for downstream decoding
                        -- This is a best-effort hack for the specific observed format
                        -- write_file(content='...', filename='...')
                        
                        -- We will manually construct a JSON string
                        -- Replacing ' with " and handling basic structure
                        -- WARNING: This is fragile. Use with caution.
                        
                        -- Alternative: Just warn the user. 
                        -- But let's try to extract key='value'
                        local jsonParts = {}
                        for k, v in argsRaw:gmatch("(%w+)='(.-)'") do
                            table.insert(jsonParts, '"' .. k .. '": "' .. v .. '"')
                        end
                        -- Try double quotes too
                        for k, v in argsRaw:gmatch('(%w+)="(.-)"') do
                            table.insert(jsonParts, '"' .. k .. '": "' .. v .. '"')
                        end
                        
                        local jsonStr = "{" .. table.concat(jsonParts, ", ") .. "}"
                        
                        -- Generate a fake ID
                        local callId = "call_" .. math.random(10000, 99999)
                        
                        table.insert(toolCalls, {
                            id = callId,
                            type = "function",
                            ["function"] = {
                                name = name,
                                arguments = jsonStr
                            }
                        })
                        
                        -- Remove the raw tool call from content to clean it up
                        cleanContent = cleanContent:gsub("<%|tool_call_start%|>" .. match:gsub("([^%w])", "%%%1") .. "<%|tool_call_end%|>", "")
                    end
                end
            end
            
            -- If we successfully parsed something, update content
            if #toolCalls > 0 then
                Logger.info("Parsed " .. #toolCalls .. " text-based tool calls.")
                content = cleanContent
            else
                toolCalls = nil -- Reset if failed
            end
            -- If still no tool calls, try to parse JSON blocks that look like tool calls
            if not toolCalls and content and (content:find("{") and content:find("}")) then
                 -- Extract first JSON block
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
            
            -- If still no tool calls, try to parse code blocks (common failure mode for weak models)
            if not toolCalls and content and (content:find("```python") or content:find("```lua") or content:find("```")) then
                -- Look for write_file('...', '...') pattern
                for match in content:gmatch("write_file%(['\"](.-)['\"],%s*['\"](.-)['\"]%)") do
                    if not toolCalls then toolCalls = {} end
                    
                    local filename, fileContent = match, nil
                    -- The gmatch above captures two groups. Let's make it more robust.
                    -- Re-matching specific call
                end
                
                -- Simplified regex for write_file specifically since that's what we're testing
                local filename, fileContent = content:match("write_file%(['\"](.-)['\"],%s*['\"](.-)['\"]%)")
                if filename and fileContent then
                     if not toolCalls then toolCalls = {} end
                     -- FIX: Tools use 'path', not 'filename'
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
                
                -- Support run_command('...')
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
