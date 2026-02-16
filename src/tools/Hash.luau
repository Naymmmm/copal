--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Config = require("../lib/Config")

local Hash = {}

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

Hash.checksumTool = {
    name = "checksum",
    description = "Calculate a checksum/hash for a file. Useful for verifying file integrity, detecting changes between tool calls, or comparing files. Uses SHA256 by default.",
    parameters = {
        type = "object",
        properties = {
            path = { type = "string", description = "Path to the file" },
            algorithm = { type = "string", description = "Hash algorithm: sha256 (default), sha1, md5" },
        },
        required = { "path" },
    },
    execute = function(args)
        if not args.path then return "Error: path required" end

        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end

        -- Check file exists
        local exists = pcall(function() return fs.readFile(args.path) end)
        if not exists then return "Error: file not found: " .. args.path end

        local algo = args.algorithm or "sha256"
        local validAlgos = { sha256 = true, sha1 = true, md5 = true }
        if not validAlgos[algo] then
            return "Error: unsupported algorithm '" .. algo .. "'. Use sha256, sha1, or md5."
        end

        -- Try platform-appropriate hash command
        local ok, result

        -- Try sha256sum/sha1sum/md5sum (Linux/macOS/Git Bash on Windows)
        local cmdMap = {
            sha256 = "sha256sum",
            sha1 = "sha1sum",
            md5 = "md5sum",
        }

        ok, result = pcall(function()
            return process.spawn(cmdMap[algo], { args.path })
        end)

        if ok and result.ok then
            -- Output format: "hash  filename"
            local hash = result.stdout:match("^(%S+)")
            if hash then
                return algo .. ": " .. hash .. "  " .. args.path
            end
        end

        -- Fallback: try certutil on Windows
        if algo == "sha256" or algo == "sha1" or algo == "md5" then
            local certAlgo = if algo == "sha256" then "SHA256" elseif algo == "sha1" then "SHA1" else "MD5"
            ok, result = pcall(function()
                return process.spawn("certutil", { "-hashfile", args.path, certAlgo })
            end)

            if ok and result.ok then
                -- certutil output has the hash on the second line
                local lines = {}
                for line in result.stdout:gmatch("[^\r\n]+") do
                    table.insert(lines, line)
                end
                if #lines >= 2 then
                    local hash = lines[2]:gsub("%s+", "")
                    return algo .. ": " .. hash .. "  " .. args.path
                end
            end
        end

        return "Error: could not compute hash. Neither " .. cmdMap[algo] .. " nor certutil available."
    end,
}

return Hash
