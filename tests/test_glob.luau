--!strict
local stdio = require("@lune/stdio")
local Glob = require("../src/tools/Glob")
local Config = require("../src/lib/Config")

local passed = 0
local failed = 0

local function test(name: string, fn: () -> boolean)
    local ok, err = pcall(fn)
    if ok and err then
        passed += 1
        stdio.write("[PASS] " .. name .. "\n")
    else
        failed += 1
        stdio.write("[FAIL] " .. name .. (if not ok then " - " .. tostring(err) else "") .. "\n")
    end
end

-- ═══════════════════════════════════════
--  Pattern Matching Unit Tests
-- ═══════════════════════════════════════

local matchGlob = Glob.matchGlob

test("matchGlob: ** matches recursive paths", function()
    return matchGlob("**/*.luau", "src/tools/Glob.luau")
end)

test("matchGlob: ** matches deeply nested", function()
    return matchGlob("**/*.luau", "a/b/c/d/file.luau")
end)

test("matchGlob: ** matches root level", function()
    return matchGlob("**/*.luau", "file.luau")
end)

test("matchGlob: single * matches within segment", function()
    return matchGlob("src/tools/*.luau", "src/tools/Glob.luau")
end)

test("matchGlob: single * does not cross segments", function()
    return not matchGlob("src/*.luau", "src/tools/Glob.luau")
end)

test("matchGlob: ? matches single char", function()
    return matchGlob("?.toml", "a.toml") and not matchGlob("?.toml", "ab.toml")
end)

test("matchGlob: literal match", function()
    return matchGlob("pesde.toml", "pesde.toml")
end)

test("matchGlob: no match on wrong extension", function()
    return not matchGlob("**/*.lua", "src/tools/Glob.luau")
end)

test("matchGlob: *.toml matches root toml files", function()
    return matchGlob("*.toml", "pesde.toml")
end)

-- ═══════════════════════════════════════
--  Integration Tests (actual filesystem)
-- ═══════════════════════════════════════

test("glob tool: **/*.luau finds Luau files", function()
    local result = Glob.globTool.execute({ pattern = "**/*.luau" })
    return result:find("%.luau") ~= nil
end)

test("glob tool: src/tools/*.luau finds tool files", function()
    local result = Glob.globTool.execute({ pattern = "src/tools/*.luau" })
    return result:find("src/tools/") ~= nil and result:find("%.luau") ~= nil
end)

test("glob tool: *.toml finds pesde.toml", function()
    local result = Glob.globTool.execute({ pattern = "*.toml" })
    return result:find("pesde.toml") ~= nil
end)

test("glob tool: no matches returns message", function()
    local result = Glob.globTool.execute({ pattern = "**/*.nonexistent_extension_xyz" })
    return result:find("No files found") ~= nil
end)

test("glob tool: max_results limits output", function()
    local result = Glob.globTool.execute({ pattern = "**/*.luau", max_results = 3 })
    local count = 0
    for _ in result:gmatch("\n") do count += 1 end
    -- Should have at most 3 file paths (+ possible truncation message)
    return count <= 5
end)

-- Security test
test("glob tool: blocks .. in restricted mode", function()
    local oldLevel = Config.security_level
    Config.security_level = "restricted"
    local result = Glob.globTool.execute({ pattern = "../../etc/passwd" })
    Config.security_level = oldLevel
    return result:find("Security Error") ~= nil
end)

-- ═══════════════════════════════════════
--  Summary
-- ═══════════════════════════════════════

print("")
print(stdio.style("bold") .. "Results: " .. passed .. " passed, " .. failed .. " failed" .. stdio.style("reset"))

if failed > 0 then
    print("SOME TESTS FAILED!")
end
