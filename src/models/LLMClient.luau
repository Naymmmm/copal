--!strict
local net = require("@lune/net")
local serde = require("@lune/serde")
local Task = require("@lune/task")
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local Monitor = require("../lib/Monitor")
local Auth = require("../core/Auth")

local LLMClient = {}

-- ═══════════════════════════════════════
--  Types
-- ═══════════════════════════════════════

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

-- ═══════════════════════════════════════
--  Usage Tracking
-- ═══════════════════════════════════════

LLMClient._usage = {
    totalRequests = 0,
    totalPromptTokens = 0,
    totalCompletionTokens = 0,
    totalTokens = 0,
    errors = 0,
    retries = 0,
    averageLatencyMs = 0,
    _latencySum = 0,
}

function LLMClient.getUsage()
    return {
        requests = LLMClient._usage.totalRequests,
        promptTokens = LLMClient._usage.totalPromptTokens,
        completionTokens = LLMClient._usage.totalCompletionTokens,
        totalTokens = LLMClient._usage.totalTokens,
        errors = LLMClient._usage.errors,
        retries = LLMClient._usage.retries,
        avgLatencyMs = LLMClient._usage.totalRequests > 0 
            and math.floor(LLMClient._usage._latencySum / LLMClient._usage.totalRequests)
            or 0,
    }
end

function LLMClient.resetUsage()
    LLMClient._usage = {
        totalRequests = 0,
        totalPromptTokens = 0,
        totalCompletionTokens = 0,
        totalTokens = 0,
        errors = 0,
        retries = 0,
        averageLatencyMs = 0,
        _latencySum = 0,
    }
end

-- ═══════════════════════════════════════
--  Internal: Request with Retry
-- ═══════════════════════════════════════

local function requestWithRetry(provider: any, body: string, model: string)
    local maxRetries = 3
    local attempt = 0
    local lastError = "Unknown Error"
    
    while attempt < maxRetries do
        attempt += 1
        if attempt > 1 then
            LLMClient._usage.retries += 1
        end
        
        local startTime = os.clock()
        
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
        
        local elapsed = math.floor((os.clock() - startTime) * 1000)

        if success and response.ok then
            local decodeSuccess, decoded = pcall(function() return serde.decode("json", response.body) end)
            if decodeSuccess then
                if decoded.choices and #decoded.choices > 0 then
                    -- Track usage if available
                    if decoded.usage then
                        LLMClient._usage.totalPromptTokens += (decoded.usage.prompt_tokens or 0)
                        LLMClient._usage.totalCompletionTokens += (decoded.usage.completion_tokens or 0)
                        LLMClient._usage.totalTokens += (decoded.usage.total_tokens or 0)
                    end
                    LLMClient._usage._latencySum += elapsed
                    LLMClient._usage.totalRequests += 1
                    
                    -- Emit usage event
                    Monitor.emit("log", "LLM", model .. " · " .. elapsed .. "ms" .. (decoded.usage and (" · " .. (decoded.usage.total_tokens or "?") .. " tok") or ""))
                    
                    return decoded
                end
                lastError = "Response missing choices field"
            else
                lastError = "Failed to parse JSON response"
            end
        elseif success then
            lastError = "HTTP " .. response.statusCode .. ": " .. response.statusMessage
            Logger.warn("Attempt " .. attempt .. "/" .. maxRetries .. " failed: " .. lastError .. " (" .. elapsed .. "ms)")
            
            if response.statusCode == 429 or response.statusCode >= 500 then
                 local waitTime = math.pow(2, attempt)
                 Logger.info("Rate-limited or server error. Retrying in " .. waitTime .. "s...")
                 Task.wait(waitTime)
            else
                 LLMClient._usage.errors += 1
                 break -- Fatal client error (400, 401, 403, etc.)
            end
        else
            lastError = "Network Request Failed: " .. tostring(response)
            Logger.warn("Attempt " .. attempt .. "/" .. maxRetries .. " failed: " .. lastError)
            LLMClient._usage.errors += 1
            Task.wait(1)
        end
    end

    Logger.error("LLM Request failed after " .. maxRetries .. " attempts. Last error: " .. lastError)
    LLMClient._usage.errors += 1
    return nil
end

-- ═══════════════════════════════════════
--  Fallback: Parse Text Tool Calls
-- ═══════════════════════════════════════

local function parseTextBasedToolCalls(content: string): ({any}?, string?)
    local toolCalls = {}
    local cleanContent = content
    
    -- Pattern 1: <|tool_call_start|>[func(args)]<|tool_call_end|>
    for match in content:gmatch("<|tool_call_start|>(.-)<|tool_call_end|>") do
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
                
                cleanContent = cleanContent:gsub("<|tool_call_start|>" .. match:gsub("([^%w])", "%%%1") .. "<|tool_call_end|>", "")
            end
        end
    end

    if #toolCalls > 0 then
        Logger.debug("Parsed " .. #toolCalls .. " text-based tool calls.")
        return toolCalls, cleanContent
    end
    
    -- Pattern 2: JSON block {"name": ..., "arguments": ...}
    local jsonBlock = content:match("```json%s*({.*})%s*```") or content:match("({.*})")
    if jsonBlock then
        local ok, parsed = pcall(function() return serde.decode("json", jsonBlock) end)
        if ok and parsed.name and parsed.arguments then
            local argsStr = ""
            if type(parsed.arguments) == "table" then
                argsStr = serde.encode("json", parsed.arguments)
            else
                argsStr = tostring(parsed.arguments)
            end
            
            table.insert(toolCalls, {
                id = "call_json_" .. math.random(10000, 99999),
                type = "function",
                ["function"] = {
                    name = parsed.name,
                    arguments = argsStr
                }
            })
            Logger.debug("Parsed JSON-based tool call: " .. parsed.name)
            return toolCalls, cleanContent
        end
    end
    
    -- Pattern 3: Code block with write_file(...) or run_command(...)
    if content:find("```") then
        local filename, fileContent = content:match("write_file%(['\"](.-)['\"'],%s*['\"](.-)['\"']%)")
        if filename and fileContent then
            table.insert(toolCalls, {
                id = "call_fb_" .. math.random(10000, 99999),
                type = "function",
                ["function"] = {
                    name = "write_file",
                    arguments = serde.encode("json", {path = filename, content = fileContent})
                }
            })
        end
        
        local cmd = content:match("run_command%(['\"](.-)['\"']%)")
        if cmd then
            table.insert(toolCalls, {
                id = "call_fb_" .. math.random(10000, 99999),
                type = "function",
                ["function"] = {
                    name = "run_command",
                    arguments = serde.encode("json", {command = cmd})
                }
            })
        end
        
        if #toolCalls > 0 then
            Logger.debug("Parsed " .. #toolCalls .. " code-block tool calls.")
            return toolCalls, cleanContent
        end
    end

    return nil, content
end

-- ═══════════════════════════════════════
--  Public: LLM Completion
-- ═══════════════════════════════════════

function LLMClient.completion(messages: {Message}, model: string, tools: {Tool}?, toolChoice: any?): (string?, {any}?)
    -- Rate limit delay (configurable)
    local delay = Config.rate_limit_delay or 0
    if delay > 0 then
        Task.wait(delay)
    end
    
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
    local data = requestWithRetry(provider, body, model)
    if not data then return nil, nil end

    if data.choices and #data.choices > 0 then
        local message = data.choices[1].message
        local content = message.content
        local toolCalls = message.tool_calls
        
        -- Fallback: Parse text-based tool calls if no native ones
        if not toolCalls and content and content:find("<|tool_call_start|>") then
            toolCalls, content = parseTextBasedToolCalls(content)
        end
        
        -- Secondary fallback if still nothing
        if not toolCalls and content and (content:find("{") and content:find("}")) then
            toolCalls, content = parseTextBasedToolCalls(content)
        end

        return content, toolCalls
    end

    return nil, nil
end

return LLMClient
