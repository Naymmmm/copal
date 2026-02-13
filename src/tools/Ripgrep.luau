--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")

local Ripgrep = {}

Ripgrep.searchTool = {
    name = "ripgrep",
    description = "Search for a text pattern in files using ripgrep (rg). Fast and respects .gitignore.",
    parameters = {
        type = "object",
        properties = {
            query = {type = "string", description = "The text or regex pattern to search for"},
            path = {type = "string", description = "The directory path to search in (default: current directory)"},
            globs = {type = "array", items = {type = "string"}, description = "Glob patterns to include/exclude (e.g. '*.luau')"},
            case_sensitive = {type = "boolean", description = "Enable case sensitive search (default: false)"}
        },
        required = {"query"}
    },
    execute = function(args)
        local query = args.query
        local path = args.path or "."
        local globs = args.globs or {}
        local caseSensitive = args.case_sensitive or false
        
        if not query then return "Error: query is required" end
        
        -- Check if rg is installed
        local check = pcall(function()
            process.spawn("rg", {"--version"})
        end)
        
        if not check then
            return "Error: 'rg' (Ripgrep) is not installed or not in PATH. Please install it or use 'list_files' / 'read_file' instead."
        end
        
        local params = {
            "--line-number",
            "--color=never",
            "--no-heading",
            "--with-filename"
        }
        
        if not caseSensitive then
            table.insert(params, "--ignore-case")
        end
        
        for _, glob in ipairs(globs) do
            table.insert(params, "--glob")
            table.insert(params, glob)
        end
        
        table.insert(params, query)
        table.insert(params, path)
        
        local success, result = pcall(function()
            return process.spawn("rg", params)
        end)
        
        if success then
            local output = result.stdout
            if #output == 0 then
                return "No matches found."
            end
            
            -- Truncate if too long (max 2000 chars)
            if #output > 2000 then
                 output = output:sub(1, 2000) .. "\n... (output truncated)"
            end
            return output
        else
            return "Error executing ripgrep: " .. tostring(result)
        end
    end
}

return Ripgrep
