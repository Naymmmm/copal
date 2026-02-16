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
        
        -- Build the full command string
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
        
        -- Use persistent shell
        local Shell = require("../core/Shell")
        local output = Shell.get():execute(fullCmd)
        return output
    end
}

return Terminal
