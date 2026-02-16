--!strict
local stdio = require("@lune/stdio")
local process = require("@lune/process")
local Shell = require("../src/core/Shell")

local function testShell()
    stdio.write(stdio.style("bold") .. "Testing Shell...\n" .. stdio.style("reset"))

    local shell = Shell.new()
    local isWindows = process.os == "windows"
    local listCmd = (shell._shell == "cmd") and "dir /b" or "ls"

    -- 1. Initial state
    if #shell._cwd > 0 then
        stdio.write("[PASS] Shell has initial CWD: " .. shell._cwd .. "\n")
    else
        stdio.write("[FAIL] Shell has no initial CWD\n")
    end

    -- 2. Echo command
    local echoResult = shell:execute("echo ShellTest123")
    if echoResult:find("ShellTest123") then
        stdio.write("[PASS] Echo command works\n")
    else
        stdio.write("[FAIL] Echo output mismatch: " .. tostring(echoResult) .. "\n")
    end

    -- 3. CWD tracking after cd
    local cwdBefore = shell._cwd
    shell:execute("cd src")
    local cwdAfter = shell._cwd
    if cwdAfter:find("src") and cwdAfter ~= cwdBefore then
        stdio.write("[PASS] CWD updated after cd: " .. cwdAfter .. "\n")
    else
        stdio.write("[FAIL] CWD not updated. Before: " .. cwdBefore .. " After: " .. cwdAfter .. "\n")
    end

    -- 4. Commands run in new CWD
    local listing = shell:execute(listCmd)
    if #listing > 0 then
        stdio.write("[PASS] Listing in new CWD returned output\n")
    else
        stdio.write("[FAIL] Listing in new CWD was empty\n")
    end

    -- 5. cd .. restores previous directory
    shell:execute("cd ..")
    local cwdRestored = shell._cwd
    -- Should be back near original
    if not cwdRestored:find("src$") then
        stdio.write("[PASS] CWD restored after cd ..: " .. cwdRestored .. "\n")
    else
        stdio.write("[FAIL] CWD still points to src: " .. cwdRestored .. "\n")
    end

    -- 6. Quoting
    local quoted = shell:quote("hello world")
    if quoted == '"hello world"' then
        stdio.write("[PASS] Quote wraps string\n")
    else
        stdio.write("[FAIL] Quote result: " .. quoted .. "\n")
    end

    -- 7. Environment variable tracking
    shell._env["COPAL_TEST_VAR"] = "test_value"
    local envResult = shell:execute(
        isWindows
            and (shell._shell == "cmd" and "echo %COPAL_TEST_VAR%" or "echo $env:COPAL_TEST_VAR")
            or "echo $COPAL_TEST_VAR"
    )
    if envResult:find("test_value") then
        stdio.write("[PASS] Environment variable propagated\n")
    else
        stdio.write("[FAIL] Env var not found in output: " .. tostring(envResult) .. "\n")
    end
    shell._env["COPAL_TEST_VAR"] = nil
end

testShell()
