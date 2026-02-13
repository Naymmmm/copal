--!strict
local fs = require("@lune/fs")

local FileSystem = {}

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
        local success, files = pcall(function() return fs.readDir(path) end)
        if success then return table.concat(files, "\n") else return "Error listing files: " .. tostring(files) end
    end
}

return FileSystem
