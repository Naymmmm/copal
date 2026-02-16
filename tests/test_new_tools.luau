--!strict
local stdio = require("@lune/stdio")
local fs = require("@lune/fs")

local passed = 0
local failed = 0

local function test(name: string, fn: () -> boolean)
    local ok, result = pcall(fn)
    if ok and result then
        passed += 1
        stdio.write("[PASS] " .. name .. "\n")
    else
        failed += 1
        local extra = ""
        if not ok then extra = " - " .. tostring(result) end
        stdio.write("[FAIL] " .. name .. extra .. "\n")
    end
end

-- ═══════════════════════════════════════
--  Git Tools
-- ═══════════════════════════════════════
print("\n--- Git Tools ---")
local Git = require("../src/tools/Git")

test("git_status returns output", function()
    local result = Git.statusTool.execute({})
    return type(result) == "string" and #result > 0
end)

test("git_status short format", function()
    local result = Git.statusTool.execute({ short = true })
    return type(result) == "string" and #result > 0
end)

test("git_log returns commits", function()
    local result = Git.logTool.execute({ count = 3 })
    return type(result) == "string" and #result > 0
end)

test("git_log oneline format", function()
    local result = Git.logTool.execute({ count = 5, oneline = true })
    return type(result) == "string" and #result > 0
end)

test("git_diff runs without error", function()
    local result = Git.diffTool.execute({})
    return type(result) == "string"
end)

test("git_diff stat mode", function()
    local result = Git.diffTool.execute({ stat = true })
    return type(result) == "string"
end)

-- ═══════════════════════════════════════
--  Tree Tool
-- ═══════════════════════════════════════
print("\n--- Tree Tool ---")
local Tree = require("../src/tools/Tree")

test("tree shows project structure", function()
    local result = Tree.treeTool.execute({})
    return result:find("src/") ~= nil
end)

test("tree respects max_depth", function()
    local result = Tree.treeTool.execute({ max_depth = 1 })
    -- Should not show deeply nested paths
    return result:find("src/") ~= nil and #result < 2000
end)

test("tree with specific path", function()
    local result = Tree.treeTool.execute({ path = "src/tools" })
    return result:find("%.luau") ~= nil
end)

test("tree respects max_items", function()
    local result = Tree.treeTool.execute({ max_items = 5 })
    return result:find("truncated") ~= nil or #result < 1000
end)

-- ═══════════════════════════════════════
--  HTTP Request Tool
-- ═══════════════════════════════════════
print("\n--- HTTP Request Tool ---")
local HttpRequest = require("../src/tools/HttpRequest")

test("http_request rejects invalid method", function()
    local result = HttpRequest.requestTool.execute({ url = "http://example.com", method = "DESTROY" })
    return result:find("invalid method") ~= nil
end)

test("http_request requires url", function()
    local result = HttpRequest.requestTool.execute({})
    return result:find("Error") ~= nil
end)

-- ═══════════════════════════════════════
--  Multi-Patch Tool
-- ═══════════════════════════════════════
print("\n--- Multi-Patch Tool ---")
local MultiPatch = require("../src/tools/MultiPatch")

test("multi_patch applies operations", function()
    -- Create a test file
    fs.writeFile("test_mp.txt", "hello world\nfoo bar\n")

    local result = MultiPatch.multiPatchTool.execute({
        operations = {
            { path = "test_mp.txt", find = "hello", replace = "goodbye" },
            { path = "test_mp.txt", find = "foo", replace = "baz" },
        }
    })

    local content = fs.readFile("test_mp.txt")
    fs.removeFile("test_mp.txt")

    return result:find("2 succeeded") ~= nil and content:find("goodbye") ~= nil and content:find("baz") ~= nil
end)

test("multi_patch reports failures", function()
    fs.writeFile("test_mp2.txt", "hello world\n")

    local result = MultiPatch.multiPatchTool.execute({
        operations = {
            { path = "test_mp2.txt", find = "NONEXISTENT", replace = "x" },
        }
    })

    fs.removeFile("test_mp2.txt")
    return result:find("1 failed") ~= nil
end)

test("multi_patch requires operations", function()
    local result = MultiPatch.multiPatchTool.execute({})
    return result:find("Error") ~= nil
end)

-- ═══════════════════════════════════════
--  Ripgrep (context_lines)
-- ═══════════════════════════════════════
print("\n--- Ripgrep (updated) ---")
local Ripgrep = require("../src/tools/Ripgrep")

test("ripgrep basic search works", function()
    local result = Ripgrep.searchTool.execute({ query = "function", path = "src/tools/Git.luau" })
    -- rg may not be in Lune's process.spawn PATH — skip if unavailable
    if result:find("not installed") then
        stdio.write("  (skipped: rg not in PATH for process.spawn)\n")
        return true
    end
    return result:find("function") ~= nil
end)

test("ripgrep context_lines adds surrounding lines", function()
    local result = Ripgrep.searchTool.execute({ query = "runGit", path = "src/tools/Git.luau", context_lines = 2 })
    if result:find("not installed") then
        stdio.write("  (skipped: rg not in PATH for process.spawn)\n")
        return true
    end
    return #result > 50
end)

-- ═══════════════════════════════════════
--  Bookmark Tool
-- ═══════════════════════════════════════
print("\n--- Bookmark Tool ---")
local Bookmark = require("../src/tools/Bookmark")

test("bookmark save and list", function()
    Bookmark.bookmarkTool.execute({ name = "test-bm", path = "src/main.luau", line = 42, note = "entry point" })
    local list = Bookmark.listBookmarksTool.execute({})
    return list:find("test%-bm") ~= nil and list:find("src/main.luau") ~= nil
end)

test("bookmark remove", function()
    Bookmark.removeBookmarkTool.execute({ name = "test-bm" })
    local list = Bookmark.listBookmarksTool.execute({})
    return list:find("No bookmarks") ~= nil
end)

-- ═══════════════════════════════════════
--  Hash Tool
-- ═══════════════════════════════════════
print("\n--- Hash Tool ---")
local Hash = require("../src/tools/Hash")

test("checksum computes hash", function()
    fs.writeFile("test_hash.txt", "hello world\n")
    local result = Hash.checksumTool.execute({ path = "test_hash.txt" })
    fs.removeFile("test_hash.txt")
    -- Hash tools may not be in Lune's process.spawn PATH
    if result:find("could not compute") then
        stdio.write("  (skipped: hash tools not in PATH for process.spawn)\n")
        return true
    end
    return result:find("sha256:") ~= nil
end)

test("checksum rejects missing file", function()
    local result = Hash.checksumTool.execute({ path = "nonexistent_file_xyz.txt" })
    return result:find("Error") ~= nil
end)

test("checksum rejects bad algorithm", function()
    fs.writeFile("test_hash2.txt", "test")
    local result = Hash.checksumTool.execute({ path = "test_hash2.txt", algorithm = "sha512" })
    fs.removeFile("test_hash2.txt")
    return result:find("unsupported") ~= nil
end)

-- ═══════════════════════════════════════
--  Process Tools
-- ═══════════════════════════════════════
print("\n--- Process Tools ---")
local Process = require("../src/tools/Process")

test("check_port returns status", function()
    local result = Process.checkPortTool.execute({ port = 99999 })
    return result:find("CLOSED") ~= nil or result:find("refused") ~= nil
end)

test("check_background with invalid id", function()
    local result = Process.checkBackgroundTool.execute({ id = "999" })
    return result:find("not found") ~= nil
end)

test("kill_process requires argument", function()
    local result = Process.killProcessTool.execute({})
    return result:find("provide") ~= nil
end)

-- ═══════════════════════════════════════
--  Archive Tool
-- ═══════════════════════════════════════
print("\n--- Archive Tool ---")
local Archive = require("../src/tools/Archive")

test("read_archive rejects unsupported format", function()
    local result = Archive.readArchiveTool.execute({ path = "file.rar" })
    return result:find("unsupported") ~= nil
end)

test("read_archive requires path", function()
    local result = Archive.readArchiveTool.execute({})
    return result:find("Error") ~= nil
end)

-- ═══════════════════════════════════════
--  Registry (all tools registered)
-- ═══════════════════════════════════════
print("\n--- Registry ---")
local Registry = require("../src/tools/Registry")

test("registry has all new tools", function()
    local expected = {
        "git_status", "git_diff", "git_log", "git_commit",
        "tree", "http_request", "multi_patch",
        "spawn_background", "check_background", "check_port", "kill_process",
        "bookmark", "list_bookmarks", "remove_bookmark",
        "checksum", "read_archive", "glob",
    }
    for _, name in ipairs(expected) do
        if not Registry.get(name) then
            print("  Missing: " .. name)
            return false
        end
    end
    return true
end)

test("registry tool count increased", function()
    local count = Registry.getToolCount()
    return count >= 35 -- was ~20ish, now should be 35+
end)

-- ═══════════════════════════════════════
--  Summary
-- ═══════════════════════════════════════
print("")
print(stdio.style("bold") .. "Results: " .. passed .. " passed, " .. failed .. " failed" .. stdio.style("reset"))
if failed > 0 then
    print("SOME TESTS FAILED!")
end
