--!strict
local process = require("@lune/process")
local Config = require("../lib/Config")

local Archive = {}

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

Archive.readArchiveTool = {
    name = "read_archive",
    description = "List the contents of an archive file (zip, tar, tar.gz, tgz) without extracting. Useful for inspecting archive contents before extraction.",
    parameters = {
        type = "object",
        properties = {
            path = { type = "string", description = "Path to the archive file" },
        },
        required = { "path" },
    },
    execute = function(args)
        if not args.path then return "Error: path required" end

        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end

        local path = args.path
        local ext = path:lower()

        local ok, result

        -- ZIP files
        if ext:match("%.zip$") then
            -- Try unzip -l
            ok, result = pcall(function()
                return process.spawn("unzip", { "-l", path })
            end)
            if ok and result.ok then
                local output = result.stdout
                if #output > 16000 then
                    output = output:sub(1, 16000) .. "\n... (truncated)"
                end
                return output
            end

            -- Fallback: PowerShell on Windows
            ok, result = pcall(function()
                return process.spawn("powershell", {
                    "-Command",
                    "Get-ChildItem -Path (New-Object System.IO.Compression.ZipArchive([System.IO.File]::OpenRead('" .. path .. "'))).Entries | Format-Table FullName, Length, LastWriteTime -AutoSize"
                })
            end)
            if ok and result.ok then return result.stdout end

            return "Error: cannot list zip contents. Neither 'unzip' nor PowerShell available."
        end

        -- TAR files (tar, tar.gz, tgz)
        if ext:match("%.tar$") or ext:match("%.tar%.gz$") or ext:match("%.tgz$") then
            ok, result = pcall(function()
                return process.spawn("tar", { "-tf", path })
            end)
            if ok and result.ok then
                local output = result.stdout
                if #output > 16000 then
                    output = output:sub(1, 16000) .. "\n... (truncated)"
                end
                return output
            end
            return "Error: 'tar' command not available."
        end

        return "Error: unsupported archive format. Supported: .zip, .tar, .tar.gz, .tgz"
    end,
}

return Archive
