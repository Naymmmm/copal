--!strict
local fs = require("@lune/fs")

local process = require("@lune/process")
local Config = require("../lib/Config")

local FileSystem = {}

-- Helper to check path safety
local function isSafePath(path: string): (boolean, string?)
    if Config.security_level == "full_access" then
        return true
    end
    
    -- Restricted Mode: Prevent directory traversal up
    -- Naive check: if path starts with "/" or contains ".."
    -- Ideally we'd resolve absolute path, but Lune doesn't have path.resolve
    -- We will assume paths are relative to CWD.
    -- If path starts with "/" or "C:", it's absolute. In restricted mode, we might want to block absolute paths 
    -- unless they start with CWD? That's hard to check without path manip.
    -- Simplified Rule: Allow relative paths, ban ".."
    
    if path:find("%.%.") then
        return false, "Path contains '..' (Parent Directory Traversal) which is blocked in Restricted Mode."
    end
    
    if path:match("^/") or path:match("^%a:") then
         -- Check if it starts with CWD
         local cwd = process.cwd
         -- Normalize slashes
         local normPath = path:gsub("\\", "/")
         local normCwd = cwd:gsub("\\", "/")
         
         if not normPath:find(normCwd, 1, true) then
             return false, "Path is outside Current Working Directory (" .. cwd .. ") in Restricted Mode."
         end
    end
    
    return true
end

FileSystem.readFileTool = {
    name = "read_file",
    description = "Read contents of a file",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file"}
        },
        required = {"path"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        local success, content = pcall(function() return fs.readFile(args.path) end)
        if success then return content else return "Error reading file: " .. tostring(content) end
    end
}

FileSystem.writeFileTool = {
    name = "write_file",
    description = "Write contents to a file (overwrites)",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file"},
            content = {type = "string", description = "Content to write"}
        },
        required = {"path", "content"}
    },
    execute = function(args)
        local path = args.path or args.filename or args.file_name or args.file_path
        if not path or not args.content then return "Error: path and content required" end
        
        local safe, reason = isSafePath(path)
        if not safe then return "Security Error: " .. tostring(reason) end

        local success, err = pcall(function() fs.writeFile(path, args.content) end)
        if success then return "Successfully wrote to " .. path else return "Error writing file: " .. tostring(err) end
    end
}

FileSystem.listFilesTool = {
    name = "list_files",
    description = "List files in a directory",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Directory path"}
        },
        required = {"path"}
    },
    execute = function(args)
        local path = args.path or "."
        
        local safe, reason = isSafePath(path)
        if not safe then return "Security Error: " .. tostring(reason) end

        local success, files = pcall(function() return fs.readDir(path) end)
        if success then return table.concat(files, "\n") else return "Error listing files: " .. tostring(files) end
    end
}

return FileSystem
