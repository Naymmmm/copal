--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Config = require("../lib/Config")

local FileSystem = {}

-- ═══════════════════════════════════════
--  Security: Path Safety Check
-- ═══════════════════════════════════════

local function isSafePath(path: string): (boolean, string?)
    if Config.security_level == "full_access" then
        return true
    end
    
    if path:find("%.%.") then
        return false, "Path contains '..' (Parent Directory Traversal) which is blocked in Restricted Mode."
    end
    
    if path:match("^/") or path:match("^%a:") then
         local cwd = process.cwd
         local normPath = path:gsub("\\", "/")
         local normCwd = cwd:gsub("\\", "/")
         
         if not normPath:find(normCwd, 1, true) then
             return false, "Path is outside Current Working Directory (" .. cwd .. ") in Restricted Mode."
         end
    end
    
    return true
end

-- ═══════════════════════════════════════
--  read_file
-- ═══════════════════════════════════════

FileSystem.readFileTool = {
    name = "read_file",
    description = "Read a file with line numbers. Supports pagination via offset/limit for large files. Returns formatted output with line numbers (e.g. '  1 │ content').",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file"},
            offset = {type = "number", description = "Starting line number, 1-indexed (default: 1)"},
            limit = {type = "number", description = "Maximum number of lines to return (default: all)"}
        },
        required = {"path"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end

        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end

        local success, content = pcall(function() return fs.readFile(args.path) end)
        if not success then return "Error reading file: " .. tostring(content) end

        -- Split into lines
        local lines = {}
        for line in (content .. "\n"):gmatch("(.-)\n") do
            table.insert(lines, line)
        end
        -- Remove trailing empty line from the split
        if #lines > 0 and lines[#lines] == "" and not content:match("\n$") then
            -- Only remove if original content didn't end with newline
        elseif #lines > 0 and lines[#lines] == "" and content:sub(-1) ~= "\n" then
            table.remove(lines)
        end

        local totalLines = #lines
        local startLine = math.max(1, args.offset or 1)
        local endLine = totalLines

        if args.limit then
            endLine = math.min(totalLines, startLine + args.limit - 1)
        end

        if startLine > totalLines then
            return "Error: offset (" .. startLine .. ") exceeds file length (" .. totalLines .. " lines)"
        end

        -- Build output with line numbers
        local result = {}

        -- Large file warning
        if #content > 50000 and not args.offset and not args.limit then
            table.insert(result, "⚠ Large file (" .. #content .. " chars, " .. totalLines .. " lines). Consider using offset/limit to read specific sections.")
            table.insert(result, "")
        end

        -- Header when paginated
        if args.offset or args.limit then
            table.insert(result, "Lines " .. startLine .. "-" .. endLine .. " of " .. totalLines .. " total:")
        end

        for i = startLine, endLine do
            table.insert(result, string.format("%4d │ %s", i, lines[i]))
        end

        return table.concat(result, "\n")
    end
}

-- ═══════════════════════════════════════
--  read_file_lines
-- ═══════════════════════════════════════

FileSystem.readFileLinesTool = {
    name = "read_file_lines",
    description = "Read specific line range from a file. More token-efficient than read_file for large files. Lines are 1-indexed.",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file"},
            start_line = {type = "number", description = "First line to read (1-indexed, default: 1)"},
            end_line = {type = "number", description = "Last line to read (inclusive, default: end of file)"}
        },
        required = {"path"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        local success, content = pcall(function() return fs.readFile(args.path) end)
        if not success then return "Error reading file: " .. tostring(content) end
        
        local lines = {}
        for line in (content .. "\n"):gmatch("(.-)\n") do
            table.insert(lines, line)
        end
        
        local startLine = math.max(1, args.start_line or 1)
        local endLine = math.min(#lines, args.end_line or #lines)
        
        if startLine > #lines then
            return "Error: start_line (" .. startLine .. ") exceeds file length (" .. #lines .. " lines)"
        end
        
        local result = {}
        for i = startLine, endLine do
            table.insert(result, string.format("%4d │ %s", i, lines[i]))
        end
        
        return "Lines " .. startLine .. "-" .. endLine .. " of " .. #lines .. " total:\n" .. table.concat(result, "\n")
    end
}

-- ═══════════════════════════════════════
--  write_file
-- ═══════════════════════════════════════

FileSystem.writeFileTool = {
    name = "write_file",
    description = "Write contents to a file (overwrites entire file). For targeted edits, use patch_file instead.",
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

-- ═══════════════════════════════════════
--  patch_file (find & replace)
-- ═══════════════════════════════════════

FileSystem.patchFileTool = {
    name = "patch_file",
    description = "Apply a targeted find-and-replace edit to a file. Much safer than write_file when multiple agents may edit the same file, since it only changes the matched section. Use read_file or read_file_lines first to see the exact text to match.",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file to patch"},
            find = {type = "string", description = "Exact text to find in the file (must match precisely, including whitespace)"},
            replace = {type = "string", description = "Replacement text"},
            all = {type = "boolean", description = "Replace all occurrences (default: false, replaces only the first)"}
        },
        required = {"path", "find", "replace"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end
        if not args.find then return "Error: find text required" end
        if args.replace == nil then return "Error: replace text required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        local readOk, content = pcall(function() return fs.readFile(args.path) end)
        if not readOk then return "Error reading file: " .. tostring(content) end
        
        -- Check if the find text exists
        local idx = content:find(args.find, 1, true)
        if not idx then
            return "Error: Could not find the specified text in " .. args.path .. ". Make sure the text matches exactly (including whitespace and line endings)."
        end
        
        local newContent
        local count = 0
        
        if args.all then
            -- Replace all occurrences
            newContent = content
            while newContent:find(args.find, 1, true) do
                local s, e = newContent:find(args.find, 1, true)
                newContent = newContent:sub(1, s - 1) .. args.replace .. newContent:sub(e + 1)
                count += 1
                if count > 100 then break end -- safety valve
            end
        else
            -- Replace first occurrence only
            local s, e = content:find(args.find, 1, true)
            newContent = content:sub(1, s - 1) .. args.replace .. content:sub(e + 1)
            count = 1
        end
        
        local writeOk, writeErr = pcall(function() fs.writeFile(args.path, newContent) end)
        if writeOk then
            return "Patched " .. args.path .. " (" .. count .. " replacement" .. (count > 1 and "s" or "") .. " made)"
        else
            return "Error writing patched file: " .. tostring(writeErr)
        end
    end
}

-- ═══════════════════════════════════════
--  delete_file
-- ═══════════════════════════════════════

FileSystem.deleteFileTool = {
    name = "delete_file",
    description = "Delete a file from the filesystem. Use with caution.",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file to delete"}
        },
        required = {"path"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        local exists = pcall(function() return fs.readFile(args.path) end)
        if not exists then return "Error: File does not exist: " .. args.path end
        
        local success, err = pcall(function() fs.removeFile(args.path) end)
        if success then return "Deleted: " .. args.path else return "Error deleting file: " .. tostring(err) end
    end
}

-- ═══════════════════════════════════════
--  create_directory
-- ═══════════════════════════════════════

FileSystem.createDirectoryTool = {
    name = "create_directory",
    description = "Create a directory (and any missing parent directories).",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path for the directory to create"}
        },
        required = {"path"}
    },
    execute = function(args)
        if not args.path then return "Error: path required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        local success, err = pcall(function() fs.writeDir(args.path) end)
        if success then return "Created directory: " .. args.path else return "Error creating directory: " .. tostring(err) end
    end
}

-- ═══════════════════════════════════════
--  list_files
-- ═══════════════════════════════════════

FileSystem.listFilesTool = {
    name = "list_files",
    description = "List files and directories in a path.",
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

-- ═══════════════════════════════════════
--  move_file (rename / move)
-- ═══════════════════════════════════════

FileSystem.moveFileTool = {
    name = "move_file",
    description = "Move or rename a file or directory.",
    parameters = {
        type = "object",
        properties = {
            source = {type = "string", description = "Current path"},
            destination = {type = "string", description = "New path"}
        },
        required = {"source", "destination"}
    },
    execute = function(args)
        if not args.source or not args.destination then return "Error: source and destination required" end
        
        local safe1, r1 = isSafePath(args.source)
        if not safe1 then return "Security Error: " .. tostring(r1) end
        local safe2, r2 = isSafePath(args.destination)
        if not safe2 then return "Security Error: " .. tostring(r2) end
        
        local success, content = pcall(function() return fs.readFile(args.source) end)
        if not success then return "Error: source file not found: " .. args.source end
        
        local writeOk, writeErr = pcall(function() fs.writeFile(args.destination, content) end)
        if not writeOk then return "Error writing destination: " .. tostring(writeErr) end
        
        local delOk, delErr = pcall(function() fs.removeFile(args.source) end)
        if not delOk then return "Warning: copied to " .. args.destination .. " but failed to remove source: " .. tostring(delErr) end
        
        return "Moved " .. args.source .. " → " .. args.destination
    end
}

-- ═══════════════════════════════════════
--  copy_file
-- ═══════════════════════════════════════

FileSystem.copyFileTool = {
    name = "copy_file",
    description = "Copy a file to a new location.",
    parameters = {
        type = "object",
        properties = {
            source = {type = "string", description = "Source file path"},
            destination = {type = "string", description = "Destination file path"}
        },
        required = {"source", "destination"}
    },
    execute = function(args)
        if not args.source or not args.destination then return "Error: source and destination required" end
        
        local safe1, r1 = isSafePath(args.source)
        if not safe1 then return "Security Error: " .. tostring(r1) end
        local safe2, r2 = isSafePath(args.destination)
        if not safe2 then return "Security Error: " .. tostring(r2) end
        
        local success, content = pcall(function() return fs.readFile(args.source) end)
        if not success then return "Error: source file not found: " .. args.source end
        
        local writeOk, writeErr = pcall(function() fs.writeFile(args.destination, content) end)
        if writeOk then return "Copied " .. args.source .. " → " .. args.destination else return "Error copying: " .. tostring(writeErr) end
    end
}

-- ═══════════════════════════════════════
--  append_file
-- ═══════════════════════════════════════

FileSystem.appendFileTool = {
    name = "append_file",
    description = "Append content to the end of a file. Creates the file if it doesn't exist. Useful for logs, adding sections, or building files incrementally without overwriting existing content.",
    parameters = {
        type = "object",
        properties = {
            path = {type = "string", description = "Path to the file"},
            content = {type = "string", description = "Content to append"}
        },
        required = {"path", "content"}
    },
    execute = function(args)
        if not args.path or not args.content then return "Error: path and content required" end
        
        local safe, reason = isSafePath(args.path)
        if not safe then return "Security Error: " .. tostring(reason) end
        
        -- Read existing content (or empty if file doesn't exist)
        local existing = ""
        local readOk, readContent = pcall(function() return fs.readFile(args.path) end)
        if readOk then existing = readContent end
        
        local writeOk, writeErr = pcall(function() fs.writeFile(args.path, existing .. args.content) end)
        if writeOk then return "Appended to " .. args.path else return "Error appending: " .. tostring(writeErr) end
    end
}

return FileSystem
