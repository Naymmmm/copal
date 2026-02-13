--!strict
local stdio = require("@lune/stdio")
local Registry = require("../src/tools/Registry")
local Communication = require("../src/tools/Communication")

local function testComm()
    stdio.write(stdio.style("bold") .. "Testing Communication Tool...\n" .. stdio.style("reset"))
    
    -- 1. Verify existence in Registry
    local tool = Registry.get("broadcast")
    if tool then
        stdio.write("[PASS] Broadcast tool registered\n")
    else
        stdio.write("[FAIL] Broadcast tool missing from Registry\n")
    end
    
    -- 2. Verify Execution
    local result = Communication.broadcastTool.execute({message = "Hello World"})
    if result:find("Message broadcasted: Hello World") then
        stdio.write("[PASS] Broadcast execution\n")
    else
        stdio.write("[FAIL] Broadcast execution result: " .. tostring(result) .. "\n")
    end
end

testComm()
