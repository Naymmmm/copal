--!strict
local Swarm = require("../src/core/Swarm")
local Config = require("../src/lib/Config")
local Monitor = require("../src/lib/Monitor")
local stdio = require("@lune/stdio")
local Task = require("@lune/task")

local function testSwarmToolUse()
    -- Ensure we have a config
    Config.load()
    if not Config.getActive().key or #Config.getActive().key == 0 then
        stdio.write(stdio.color("red") .. "Skipping test: No API Key configured.\n" .. stdio.color("reset"))
        return
    end

    stdio.write(stdio.style("bold") .. "Testing Swarm Agent Tool Usage...\n" .. stdio.style("reset"))
    
    -- Subscribe to monitor to see tool calls
    Monitor.subscribe(function(event)
        if event.type == "tool_call" then
            stdio.write(stdio.color("magenta") .. "[Monitor] Tool Call: " .. event.data.tool .. "\n" .. stdio.color("reset"))
        elseif event.type == "tool_result" then
            stdio.write(stdio.color("cyan") .. "[Monitor] Tool Result: " .. tostring(event.data.result) .. "\n" .. stdio.color("reset"))
        elseif event.type == "log" then
            stdio.write(stdio.color("blue") .. "[Monitor] Log: " .. event.data .. "\n" .. stdio.color("reset"))
        elseif event.type == "completion" then
            stdio.write(stdio.color("green") .. "[Monitor] Completion: " .. event.data .. "\n" .. stdio.color("reset"))
        end
    end)

    local swarm = Swarm.new(1)
    -- Tasks that specifically forces tool use
    local tasks = {
        "Create a file named 'agent_tool_test.txt' with the content 'Tool use verified'."
    }
    
    local results = swarm:execute(tasks)
    
    local fs = require("@lune/fs")
    if fs.isFile("agent_tool_test.txt") then
        local content = fs.readFile("agent_tool_test.txt")
        if content == "Tool use verified" then
            stdio.write(stdio.color("green") .. "[PASS] Agent successfully created file.\n" .. stdio.color("reset"))
            fs.removeFile("agent_tool_test.txt")
        else
            stdio.write(stdio.color("red") .. "[FAIL] File content mismatch: " .. content .. "\n" .. stdio.color("reset"))
        end
    else
        stdio.write(stdio.color("red") .. "[FAIL] Agent did not create file.\n" .. stdio.color("reset"))
    end
end

testSwarmToolUse()
