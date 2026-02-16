--!strict
local stdio = require("@lune/stdio")
local Terminal = require("../src/tools/Terminal")
local Shell = require("../src/core/Shell")

local function testTerminal()
    stdio.write(stdio.style("bold") .. "Testing Terminal Tool...\n" .. stdio.style("reset"))

    local shell = Shell.get()
    local listCmd = (shell._shell == "cmd") and "dir /b" or "ls"

    -- 1. Basic echo
    local echoOut = Terminal.runCommandTool.execute({command = "echo TerminalTest456"})
    if echoOut:find("TerminalTest456") then
        stdio.write("[PASS] Terminal echo\n")
    else
        stdio.write("[FAIL] Terminal echo output: " .. tostring(echoOut) .. "\n")
    end

    -- 2. Missing command arg
    local missingOut = Terminal.runCommandTool.execute({})
    if missingOut:find("[Ee]rror") or missingOut:find("[Nn]o command") or #missingOut == 0 then
        stdio.write("[PASS] Terminal handles missing command\n")
    else
        stdio.write("[FAIL] Terminal missing command: " .. tostring(missingOut) .. "\n")
    end

    -- 3. CD persistence through Terminal tool
    local cwdBefore = shell._cwd
    Terminal.runCommandTool.execute({command = "cd src"})
    local cwdAfter = shell._cwd
    if cwdAfter:find("src") and cwdAfter ~= cwdBefore then
        stdio.write("[PASS] Terminal cd updates Shell CWD\n")
    else
        stdio.write("[FAIL] Terminal cd did not update CWD. Before: " .. cwdBefore .. " After: " .. cwdAfter .. "\n")
    end

    -- 4. Subsequent command runs in new CWD
    local listing = Terminal.runCommandTool.execute({command = listCmd})
    if #listing > 0 then
        stdio.write("[PASS] Terminal listing after cd\n")
    else
        stdio.write("[FAIL] Terminal listing empty after cd\n")
    end

    -- Restore
    Terminal.runCommandTool.execute({command = "cd .."})
end

testTerminal()
