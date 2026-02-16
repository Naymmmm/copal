--!strict
local stdio = require("@lune/stdio")
local Monitor = require("../src/lib/Monitor")
local Registry = require("../src/tools/Registry")
local FileSystem = require("../src/tools/FileSystem")
local Terminal = require("../src/tools/Terminal")

local function testTools()
    stdio.write(stdio.style("bold") .. "Testing Tools & Monitor...\n" .. stdio.style("reset"))
    
    -- 1. Test Monitor
    local monitorReceived = false
    Monitor.subscribe(function(event)
        if event.type == "log" and event.data == "Test Message" then
            monitorReceived = true
            stdio.write("[PASS] Monitor received event\n")
        end
    end)
    Monitor.log("TestSystem", "Test Message")
    
    -- 2. Test Registry
    local definitions = Registry.getAllDefinitions()
    if #definitions >= 2 then
        stdio.write("[PASS] Registry has tools\n")
    else
        stdio.write("[FAIL] Registry missing tools\n")
    end
    
    -- 3. Test FileSystem
    local testFile = "test_write.txt"
    FileSystem.writeFileTool.execute({path = testFile, content = "Hello Tools"})
    local content = FileSystem.readFileTool.execute({path = testFile})
    if content:find("Hello Tools") then
        stdio.write("[PASS] FileSystem Read/Write\n")
    else
        stdio.write("[FAIL] FileSystem content mismatch: " .. tostring(content) .. "\n")
    end
    -- Cleanup
    local fs = require("@lune/fs")
    if fs.isFile(testFile) then fs.removeFile(testFile) end
    
    -- 4. Test Terminal
    local output = Terminal.runCommandTool.execute({command = "echo HelloTerminal"})
    if output:find("HelloTerminal") then
        stdio.write("[PASS] Terminal Command\n")
    else
        stdio.write("[FAIL] Terminal output mismatch: " .. tostring(output) .. "\n")
    end
end

testTools()
