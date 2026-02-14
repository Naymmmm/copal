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

local Wizard = require("./ui/Wizard")

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
        Wizard.start()
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
            -- handled earlier
        end
    end

    -- 3. Interactive Mode Selection
    if mode == "interactive" then
        while true do
            TUI.drawHeader("Interactive Selection")
            TUI.blank()
            
            local selection = TUI.menu({
                {label = "Swarm Mode",    value = "swarm",    description = "Single task → multiple agents"},
                {label = "Director Mode", value = "director", description = "Plan & Execute with review loop"},
                {label = "Company Mode",  value = "company",  description = "CEO → Directors → Agents"},
                {label = "Settings",      value = "settings", description = "Providers, models, security"},
            })
            
            if selection == "swarm" or selection == "director" or selection == "company" then
                mode = selection
                break
            elseif selection == "settings" then
                Wizard.settingsMenu()
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
        TUI.drawBox("Swarm Mode", "Running agents directly without Director supervision.\nUse Director Mode for complex planning.")
        
        local swarm = Swarm.new(5)
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
