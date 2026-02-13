--!strict
local process = require("@lune/process")

local Terminal = {}

Terminal.runCommandTool = {
    name = "run_command",
    description = "Run a shell command",
    parameters = {
        type = "object",
        properties = {
            command = {type = "string", description = "Command to run"},
            args = {type = "array", items = {type = "string"}, description = "Arguments"}
        },
        required = {"command"}
    },
    execute = function(args)
        if not args.command then return "Error: command required" end
        local cmdArgs = args.args or {}
        
        local prog = args.command
        local params = cmdArgs
        
        -- OS Detection and Shell Wrapping
        if process.os == "windows" then
            -- Wrap in cmd /c
            -- We need to construct the full command string for cmd /c
            -- Simple approach: use "cmd", {"/c", command .. " " .. table.concat(args, " ")}
            -- But simplistic concatenation is dangerous/complex with quotes.
            -- However, for this MVP tool, let's try to execute directly if possible, or wrap.
            -- Echo is a shell builtin, so we MUST use shell.
            -- Most users want shell execution.
            
            -- Re-construct command line
            local fullCmd = prog
            for _, arg in ipairs(params) do
                fullCmd = fullCmd .. " " .. arg
            end
            
            prog = "cmd"
            params = {"/c", fullCmd}
        else
            -- Linux/Mac - use sh -c
            local fullCmd = prog
            for _, arg in ipairs(params) do
                fullCmd = fullCmd .. " " .. arg
            end
            
            prog = "sh"
            params = {"-c", fullCmd}
        end
        
        local success, result = pcall(function()
            return process.create(prog, params)
        end)
        
        if success then
            -- Read output
            local stdout = ""
            local stderr = ""
            
            pcall(function()
                local chunk = result.stdout:read()
                while chunk do
                    stdout = stdout .. chunk
                    chunk = result.stdout:read()
                end
            end)
            
            pcall(function()
                local chunk = result.stderr:read()
                while chunk do
                    stderr = stderr .. chunk
                    chunk = result.stderr:read()
                end
            end)
             
            local output = stdout
            if #stderr > 0 then
                output = output .. "\nSTDERR:\n" .. stderr
            end
            return output
        else
            return "Error running command: " .. tostring(result)
        end
    end
}

return Terminal
