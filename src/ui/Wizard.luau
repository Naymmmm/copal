--!strict
local stdio = require("@lune/stdio")
local TUI = require("./TUI")
local Auth = require("../core/Auth")
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")

local Wizard = {}

-- Helper to select a model with search/filter
local function selectModel(role: string, default: string, apiKey: string): string
    local models = Auth.fetchModels(apiKey)
    local fetchFailed = false
    
    if not models or #models == 0 then
        Logger.warn("Could not fetch models. Please enter model names manually.")
        models = {}
        fetchFailed = true
    end

    local popularKeywords = {
        "gpt-4o", "claude-3-5-sonnet", "gemini-2.0-flash", "deepseek-r1", 
        "llama-3.1-70b", "o1-preview", "liquid/lfm", "minimax"
    }

    -- Sort models: Popular ones first, then alphabetical
    if not fetchFailed and models then
        table.sort(models, function(a, b)
            local aPop = false
            local bPop = false
            for _, kw in ipairs(popularKeywords) do
                if a:lower():find(kw) then aPop = true end
                if b:lower():find(kw) then bPop = true end
            end
            
            if aPop and not bPop then return true end
            if not aPop and bPop then return false end
            return a < b
        end)
    end

    local currentFilter = ""
    
    while true do
        TUI.drawHeader("Model Selection: " .. role)
        stdio.write("Role: " .. role .. "\n")
        stdio.write("Default: " .. default .. "\n")
        if #currentFilter > 0 then
            stdio.write("Filter: " .. stdio.color("yellow") .. currentFilter .. stdio.color("reset") .. "\n")
        end
        stdio.write("----------------------------------------\n")
        
        local filteredModels = {}
        if not fetchFailed then
            for _, m in ipairs(models) do
                if #currentFilter == 0 or m:lower():find(currentFilter:lower()) then
                    table.insert(filteredModels, m)
                end
            end
            
            -- Show results (paged or limited)
            local limit = 10
            for i = 1, math.min(#filteredModels, limit) do
                stdio.write(string.format("%d. %s\n", i, filteredModels[i]))
            end
            
            if #filteredModels == 0 then
                stdio.write(stdio.color("red") .. "No models match your filter.\n" .. stdio.color("reset"))
            elseif #filteredModels > limit then
                stdio.write(string.format("... (%d more matches)\n", #filteredModels - limit))
            end
            
            stdio.write("\nOptions:\n")
            stdio.write("- Type a number to select.\n")
            stdio.write("- Type text to search/filter.\n")
            stdio.write("- Press Enter to use Default.\n")
            if #currentFilter > 0 then
                stdio.write("- Type 'clear' to reset filter.\n")
            end
        else
            stdio.write("Enter the model ID manually.\n")
        end
        
        local input = TUI.prompt(">")
        
        -- Empty input -> Default
        if input == "" then
            return default
        end
        
        -- Clear filter
        if input:lower() == "clear" then
            currentFilter = ""
            continue
        end
        
        -- Check if number selection
        local num = tonumber(input)
        if num and not fetchFailed then
            if filteredModels[num] then
                return filteredModels[num]
            end
        end
        
        -- If manual entry (fetch failed) or just typing a model name explicitly
        if fetchFailed then
            return input
        end
        
        -- Otherwise treat as filter
        -- If the user typed something that isn't a number, update filter
        if not num then
            currentFilter = input
        end
    end
end

function Wizard.settingsMenu()
    while true do
        TUI.drawHeader("Configuration Settings")
        stdio.write("Current Provider: " .. Config.active_provider .. "\n")
        stdio.write("----------------------------------------\n")
        stdio.write("1. Change Active Provider\n")
        stdio.write("2. Update API Key (Current Provider)\n")
        stdio.write("3. Update Model Selection\n")
        stdio.write("4. Back to Main Menu\n")
        
        local selection = TUI.prompt("Select Option")
        
        if selection == "1" then
            Wizard.start(true) -- Re-run full setup for simplicity regarding provider switch
            return
        elseif selection == "2" then
            local provider = Config.getActive()
            local newKey = TUI.promptSecret("Enter new API Key for " .. Config.active_provider)
            if #newKey > 0 then
                if Auth.validateKey(newKey) then
                    provider.key = newKey
                    Config.save()
                    Logger.success("API Key updated.")
                    Task.wait(1)
                else
                    Logger.error("Invalid Key.")
                    Task.wait(1)
                end
            end
        elseif selection == "3" then
            local provider = Config.getActive()
            if not provider.key or #provider.key == 0 then
                Logger.error("Set API Key first.")
                Task.wait(1)
                continue
            end
            
            provider.models.low = selectModel("Swarm (Low)", provider.models.low, provider.key)
            provider.models.medium = selectModel("Director (Medium)", provider.models.medium, provider.key)
            provider.models.high = selectModel("CEO (High)", provider.models.high, provider.key)
            Config.save()
            Logger.success("Models updated.")
            Task.wait(1)
        elseif selection == "4" then
            return
        end
    end
end
    
function Wizard.start(skipWelcome: boolean?)
    if not skipWelcome then
        TUI.drawHeader("Copal Setup Wizard")
        stdio.write("Welcome to Copal! Let's get you set up.\n\n")
    end

    -- 1. Provider Selection
    TUI.drawHeader("Select AI Provider")
    local providers = {"opencode", "openrouter", "openai", "custom"}
    for i, p in ipairs(providers) do
        stdio.write(string.format("%d. %s\n", i, p))
    end
    
    local selectedProvider = "opencode"
    while true do
        local selection = TUI.prompt("Enter number (Default: 1)")
        if selection == "" then
            break
        end
        local num = tonumber(selection)
        if num and providers[num] then
            selectedProvider = providers[num]
            break
        end
        Logger.warn("Invalid selection.")
    end

    Auth.setProvider(selectedProvider)
    local providerConfig = Config.providers[selectedProvider]

    if selectedProvider == "custom" then
        local url = TUI.prompt("Enter Base URL (Default: " .. providerConfig.url .. ")")
        if #url > 0 then
            providerConfig.url = url
            Config.providers.custom.url = url
        end
    end

    -- 2. API Key
    local apiKey = ""
    local skipKeyEntry = false
    
    if providerConfig.key and #providerConfig.key > 0 then
        stdio.write("Existing API Key found.\n")
        local change = TUI.prompt("Update API Key? (y/N)")
        if change:lower() ~= "y" then
            apiKey = providerConfig.key
            skipKeyEntry = true
        end
    end

    if not skipKeyEntry then
        while true do
            apiKey = TUI.promptSecret("Enter API Key for " .. selectedProvider)
            if #apiKey == 0 then
                Logger.error("API Key cannot be empty.")
                continue
            end
            
            stdio.write("Validating key...\n")
            if Auth.validateKey(apiKey) then
                Logger.success("API Key valid!")
                providerConfig.key = apiKey
                break
            else
                Logger.error("Invalid API Key or connection failed. Please try again.")
                local retry = TUI.prompt("Retry? (y/n)")
                if retry:lower() ~= "y" then
                    providerConfig.key = apiKey 
                    break
                end
            end
        end
    end

    -- 3. Fetch Models (Calls static helper)
    providerConfig.models.low = selectModel("Swarm Agents (Low Cost)", providerConfig.models.low or "gpt-4o-mini", apiKey)
    providerConfig.models.medium = selectModel("Director (Coordination)", providerConfig.models.medium or "gpt-4o", apiKey)
    providerConfig.models.high = selectModel("Company CEO (High Intelligence)", providerConfig.models.high or "o1", apiKey)

    -- 4. Save Config
    TUI.drawHeader("Review Configuration")
    stdio.write("Provider: " .. selectedProvider .. "\n")
    local censoredKey = "sk-..." .. string.sub(apiKey, -4)
    if #apiKey < 10 then censoredKey = "(hidden)" end
    
    stdio.write("API Key: " .. censoredKey .. "\n")
    stdio.write("Low Model: " .. providerConfig.models.low .. "\n")
    stdio.write("Medium Model: " .. providerConfig.models.medium .. "\n")
    stdio.write("High Model: " .. providerConfig.models.high .. "\n")
    
    local confirm = TUI.prompt("Save configuration? (y/n)")
    if confirm:lower() == "y" then
        Config.save()
        Logger.success("Configuration saved to " .. Config.configFile)
    else
        Logger.warn("Configuration NOT saved.")
    end
end

return Wizard
