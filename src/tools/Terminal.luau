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
        
        local os = process.os
        local shellPref = require("../lib/Config").shell_preference
        
        -- Determine Shell
        if os == "windows" then
            if shellPref == "cmd" then
                 prog = "cmd"
                 params = {"/c", table.concat(params, " ")}
            elseif shellPref == "powershell" then
                 prog = "powershell"
                 params = {"-Command", table.concat(params, " ")}
            elseif shellPref == "pwsh" then
                 prog = "pwsh"
                 params = {"-Command", table.concat(params, " ")}
            else
                -- Auto detection
                -- Try pwsh first
                local check = pcall(function() 
                    process.spawn("pwsh", {"-v"}) 
                end)
                
                if check then
                    prog = "pwsh"
                    params = {"-Command", table.concat(params, " ")}
                else
                     -- Fallback to powershell
                     local checkPS = pcall(function() 
                        process.spawn("powershell", {"-v"}) 
                     end)
                     if checkPS then
                         prog = "powershell"
                         params = {"-Command", table.concat(params, " ")}
                     else
                         -- Fallback to cmd
                         prog = "cmd"
                         params = {"/c", table.concat(params, " ")}
                     end
                end
            end
        else
            -- Linux/Mac
            if shellPref == "bash" then
                prog = "bash"
                params = {"-c", table.concat(params, " ")}
            else
                 -- Auto: Default to bash
                 prog = "bash"
                 params = {"-c", table.concat(params, " ")}
            end
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
