--!strict
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Task = require("@lune/task")
local Auth = require("./core/Auth")
local TUI = require("./ui/TUI")
local Logger = require("./lib/Logger")
local Swarm = require("./core/Swarm")
local Director = require("./core/Director")
local Company = require("./core/Company")
local Config = require("./lib/Config")

local function main()
    TUI.drawHeader("Initializing...")

    -- 0. Check for Config/Setup
    local args = process.args
    local forceSetup = false
    for _, arg in ipairs(args) do
        if arg == "--setup" then forceSetup = true end
    end

    Config.load()
    if forceSetup or not Config.exists() then
        local Wizard = require("./ui/Wizard")
        Wizard.start()
        -- Reload config after wizard
        Config.load()
    end

    -- 1. Authentication
    if not Auth.login() then
        Logger.error("Authentication failed. Run with --setup to configure.")
        process.exit(1)
    end

    -- 2. Argument Parsing
    local mode = "interactive"
    local inputTask = nil

    for i, arg in ipairs(args) do
        if arg == "--mode" and args[i+1] then
            mode = args[i+1]
        elseif arg == "--task" or arg == "--goal" or arg == "--mission" and args[i+1] then
            inputTask = args[i+1]
        elseif arg == "--setup" then
            -- handled earlier but good for completeness
        end
    end

    -- 3. Mode Selection
    if mode == "interactive" then
        while true do
            TUI.drawHeader("Interactive Selection")
            stdio.write("1. Swarm Mode (Single Task)\n")
            stdio.write("2. Director Mode (Plan & Execute)\n")
            stdio.write("3. Company Mode (CEO & Departments)\n")
            stdio.write("4. Settings (Providers & Models)\n")
            
            local selection = TUI.prompt("Select Mode (1-4)")
            if selection == "1" then 
                mode = "swarm"
                break
            elseif selection == "2" then 
                mode = "director"
                break
            elseif selection == "3" then 
                mode = "company"
                break
            elseif selection == "4" then
                local Wizard = require("./ui/Wizard")
                Wizard.settingsMenu()
                -- Loop back to selection after settings
            else
                Logger.error("Invalid selection.")
                Task.wait(1)
            end
        end
    end

    TUI.drawHeader(string.upper(mode) .. " MODE")

    -- 4. Execution
    if mode == "swarm" then
        local taskDesc = inputTask or TUI.prompt("Enter task for Swarm")
        TUI.drawBox("Swarm Mode Activated", "Running agents directly without Director supervision.\nUse Director Mode for complex planning.")
        
        local swarm = Swarm.new(5)
        -- In simple swarm mode, we treat the task as a single item or split it simply?
        -- The Swarm class expects a list of subtasks.
        -- Let's just wrap it in a list for now or split by newlines.
        Logger.info("Dispatching swarm...")
        swarm:execute({taskDesc})

    elseif mode == "director" then
        local goal = inputTask or TUI.prompt("Enter goal for Director")
        local director = Director.new()
        director:planAndExecute(goal)

    elseif mode == "company" then
        local mission = inputTask or TUI.prompt("Enter mission for Company CEO")
        local company = Company.new()
        company:start(mission)

    else
        Logger.error("Unknown mode: " .. mode)
    end
end

main()
