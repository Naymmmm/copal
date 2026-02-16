--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Config = require("../lib/Config")

local MultiPatch = {}

local function isSafePath(path: string): (boolean, string?)
    if Config.security_level == "full_access" then
        return true
    end
    if path:find("%.%.") then
        return false, "Path contains '..' which is blocked in Restricted Mode."
    end
    if path:match("^/") or path:match("^%a:") then
        local cwd = process.cwd
        local normPath = path:gsub("\\", "/")
        local normCwd = cwd:gsub("\\", "/")
        if not normPath:find(normCwd, 1, true) then
            return false, "Path is outside CWD in Restricted Mode."
        end
    end
    return true
end

MultiPatch.multiPatchTool = {
    name = "multi_patch",
    description = "Apply multiple find-and-replace edits across one or more files in a single call. More efficient than calling patch_file repeatedly. Each operation specifies a file, text to find, and replacement. Operations are applied in order. If any operation fails, previous successful operations are NOT rolled back.",
    parameters = {
        type = "object",
        properties = {
            operations = {
                type = "array",
                items = {
                    type = "object",
                    properties = {
                        path = { type = "string", description = "File path" },
                        find = { type = "string", description = "Exact text to find" },
                        replace = { type = "string", description = "Replacement text" },
                        all = { type = "boolean", description = "Replace all occurrences (default: false)" },
                    },
                    required = { "path", "find", "replace" },
                },
                description = "List of patch operations to apply",
            },
        },
        required = { "operations" },
    },
    execute = function(args)
        if not args.operations or type(args.operations) ~= "table" or #args.operations == 0 then
            return "Error: operations array required (non-empty)"
        end

        local results: { string } = {}
        local successCount = 0
        local failCount = 0

        -- Cache file contents to avoid re-reading files modified in earlier ops
        local fileCache: { [string]: string } = {}

        for i, op in ipairs(args.operations) do
            local label = "#" .. i .. " (" .. (op.path or "?") .. ")"

            if not op.path or not op.find or op.replace == nil then
                failCount += 1
                table.insert(results, "FAIL " .. label .. ": missing path, find, or replace")
                continue
            end

            local safe, reason = isSafePath(op.path)
            if not safe then
                failCount += 1
                table.insert(results, "FAIL " .. label .. ": " .. tostring(reason))
                continue
            end

            -- Read file (from cache or disk)
            local content = fileCache[op.path]
            if not content then
                local readOk, readContent = pcall(function() return fs.readFile(op.path) end)
                if not readOk then
                    failCount += 1
                    table.insert(results, "FAIL " .. label .. ": cannot read file: " .. tostring(readContent))
                    continue
                end
                content = readContent
            end

            -- Find the text
            local idx = content:find(op.find, 1, true)
            if not idx then
                failCount += 1
                table.insert(results, "FAIL " .. label .. ": text not found")
                continue
            end

            -- Replace
            local newContent
            local count = 0

            if op.all then
                newContent = content
                while newContent:find(op.find, 1, true) do
                    local s, e = newContent:find(op.find, 1, true)
                    newContent = newContent:sub(1, s - 1) .. op.replace .. newContent:sub(e + 1)
                    count += 1
                    if count > 100 then break end
                end
            else
                local s, e = content:find(op.find, 1, true)
                newContent = content:sub(1, s - 1) .. op.replace .. content:sub(e + 1)
                count = 1
            end

            -- Write back
            local writeOk, writeErr = pcall(function() fs.writeFile(op.path, newContent) end)
            if writeOk then
                fileCache[op.path] = newContent
                successCount += 1
                table.insert(results, "OK   " .. label .. ": " .. count .. " replacement(s)")
            else
                failCount += 1
                table.insert(results, "FAIL " .. label .. ": write error: " .. tostring(writeErr))
            end
        end

        local summary = successCount .. " succeeded, " .. failCount .. " failed out of " .. #args.operations .. " operations\n\n"
        return summary .. table.concat(results, "\n")
    end,
}

return MultiPatch
