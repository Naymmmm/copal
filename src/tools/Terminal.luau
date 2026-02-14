--!strict
local process = require("@lune/process")

local Terminal = {}

Terminal.runCommandTool = {
    name = "run_command",
    description = "Run a shell command. Put the FULL command in the 'command' field (e.g. 'mkdir test && echo done'). The 'args' field is optional.",
    parameters = {
        type = "object",
        properties = {
            command = {type = "string", description = "Full command to run (e.g. 'git status', 'npm install')"},
            args = {type = "array", items = {type = "string"}, description = "Optional extra arguments"}
        },
        required = {"command"}
    },
    execute = function(args)
        if not args.command then return "Error: command required" end
        
        -- Build the full command string (robust: handle args as string OR table OR nil)
        local fullCmd = tostring(args.command)
        if args.args then
            if type(args.args) == "table" then
                local extra = table.concat(args.args, " ")
                if #extra > 0 then
                    fullCmd = fullCmd .. " " .. extra
                end
            elseif type(args.args) == "string" then
                fullCmd = fullCmd .. " " .. args.args
            end
        end
        
        local os = process.os
        local prog, params
        local shellPref = require("../lib/Config").shell_preference
        
        -- Determine Shell and wrap command
        if os == "windows" then
            if shellPref == "cmd" then
                prog = "cmd"
                params = {"/c", fullCmd}
            elseif shellPref == "powershell" then
                prog = "powershell"
                params = {"-Command", fullCmd}
            elseif shellPref == "pwsh" then
                prog = "pwsh"
                params = {"-Command", fullCmd}
            else
                -- Auto detection: try pwsh first
                local check = pcall(function() 
                    process.spawn("pwsh", {"-v"}) 
                end)
                
                if check then
                    prog = "pwsh"
                    params = {"-Command", fullCmd}
                else
                    local checkPS = pcall(function() 
                        process.spawn("powershell", {"-v"}) 
                    end)
                    if checkPS then
                        prog = "powershell"
                        params = {"-Command", fullCmd}
                    else
                        prog = "cmd"
                        params = {"/c", fullCmd}
                    end
                end
            end
        else
            -- Linux/Mac
            prog = "bash"
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
