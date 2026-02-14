--!strict
local stdio = require("@lune/stdio")
local Task = require("@lune/task")
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
        
        TUI.section("Configuration")
        TUI.sectionItem("▸", "cyan", "Role: " .. role)
        TUI.sectionItem("▸", "cyan", "Default: " .. stdio.style("dim") .. default .. stdio.style("reset"))
        if #currentFilter > 0 then
            TUI.sectionItem("▸", "yellow", "Filter: " .. currentFilter)
        end
        TUI.sectionEnd()
        
        local filteredModels = {}
        if not fetchFailed then
            for _, m in ipairs(models) do
                if #currentFilter == 0 or m:lower():find(currentFilter:lower()) then
                    table.insert(filteredModels, m)
                end
            end
            
            TUI.section("Available Models")
            local limit = 10
            for i = 1, math.min(#filteredModels, limit) do
                TUI.sectionItem(tostring(i), "green", filteredModels[i])
            end
            
            if #filteredModels == 0 then
                TUI.sectionItem("✘", "red", "No models match your filter.")
            elseif #filteredModels > limit then
                TUI.sectionItem("…", "white", "(" .. (#filteredModels - limit) .. " more matches)")
            end
            TUI.sectionEnd()
            
            TUI.blank()
            TUI.section("Options")
            TUI.sectionItem("1-9", "cyan", "Select by number")
            TUI.sectionItem("abc", "cyan", "Type to search/filter")
            TUI.sectionItem("↵", "cyan", "Press Enter for default")
            if #currentFilter > 0 then
                TUI.sectionItem("×", "yellow", "Type 'clear' to reset filter")
            end
            TUI.sectionEnd()
        else
            TUI.section("Manual Entry")
            TUI.sectionItem("▸", "yellow", "Enter the model ID manually")
            TUI.sectionEnd()
        end
        
        local input = TUI.prompt("Model")
        
        if input == "" then
            return default
        end
        
        if input:lower() == "clear" then
            currentFilter = ""
            continue
        end
        
        local num = tonumber(input)
        if num and not fetchFailed then
            if filteredModels[num] then
                return filteredModels[num]
            end
        end
        
        if fetchFailed then
            return input
        end
        
        if not num then
            currentFilter = input
        end
    end
end

function Wizard.settingsMenu()
    while true do
        TUI.drawHeader("Settings")
        
        TUI.section("Current Configuration")
        TUI.sectionItem("▸", "cyan", "Provider: " .. stdio.style("bold") .. Config.active_provider .. stdio.style("reset"))
        TUI.sectionItem("▸", "cyan", "Security: " .. stdio.style("bold") .. (Config.security_level or "restricted") .. stdio.style("reset"))
        TUI.sectionItem("▸", "cyan", "Rate Limit: " .. stdio.style("bold") .. tostring(Config.rate_limit_delay or 0) .. "s" .. stdio.style("reset") .. "  Max Agents: " .. stdio.style("bold") .. tostring(Config.max_agents or 5) .. stdio.style("reset"))
        TUI.sectionEnd()
        TUI.blank()
        
        local selection = TUI.menu({
            {label = "Change Provider",     value = "provider",   description = "Switch AI provider"},
            {label = "Update API Key",      value = "apikey",     description = "For " .. Config.active_provider},
            {label = "Model Selection",     value = "models",     description = "Configure per-tier models"},
            {label = "Security Level",      value = "security",   description = (Config.security_level or "restricted")},
            {label = "Rate Limit Delay",    value = "ratelimit",  description = tostring(Config.rate_limit_delay or 0) .. "s between LLM calls"},
            {label = "Max Agents",          value = "maxagents",  description = tostring(Config.max_agents or 5) .. " concurrent agents"},
            {label = "Back",                value = "back",       description = "Return to main menu"},
        })
        
        if selection == "provider" then
            Wizard.start(true)
            return
        elseif selection == "apikey" then
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
        elseif selection == "models" then
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
        elseif selection == "security" then
            TUI.drawHeader("Security Level")
            TUI.blank()
            
            local secSel = TUI.menu({
                {label = "Restricted", value = "restricted", description = "Agents confined to CWD, commands need approval"},
                {label = "Full Access", value = "full_access", description = "Agents can roam freely, commands auto-run"},
            })
            
            if secSel then
                Config.security_level = secSel
                Config.save()
                Logger.success("Security level: " .. secSel)
                Task.wait(1)
            end
        elseif selection == "ratelimit" then
            TUI.drawHeader("Rate Limit Delay")
            TUI.blank()
            local delaySel = TUI.menu({
                {label = "None (0s)",    value = "0",    description = "No delay (fastest)"},
                {label = "0.25 seconds", value = "0.25", description = "Light throttle"},
                {label = "0.5 seconds",  value = "0.5",  description = "Moderate throttle"},
                {label = "1 second",     value = "1",    description = "Heavy throttle"},
                {label = "2 seconds",    value = "2",    description = "Very slow"},
                {label = "Custom",       value = "custom", description = "Enter a custom value"},
            })
            if delaySel == "custom" then
                local val = TUI.prompt("Delay in seconds (e.g. 0.75)")
                local num = tonumber(val)
                if num and num >= 0 then
                    Config.rate_limit_delay = num
                    Config.save()
                    Logger.success("Rate limit delay: " .. num .. "s")
                else
                    Logger.error("Invalid number.")
                end
            elseif delaySel then
                Config.rate_limit_delay = tonumber(delaySel) or 0
                Config.save()
                Logger.success("Rate limit delay: " .. delaySel .. "s")
            end
            Task.wait(1)
        elseif selection == "maxagents" then
            TUI.drawHeader("Max Concurrent Agents")
            TUI.blank()
            local agentSel = TUI.menu({
                {label = "2 agents",  value = "2",  description = "Minimal"},
                {label = "3 agents",  value = "3",  description = "Light swarm"},
                {label = "5 agents",  value = "5",  description = "Default"},
                {label = "8 agents",  value = "8",  description = "Large swarm"},
                {label = "10 agents", value = "10", description = "Max parallel"},
                {label = "Custom",    value = "custom", description = "Enter a custom value"},
            })
            if agentSel == "custom" then
                local val = TUI.prompt("Max agents (1-20)")
                local num = tonumber(val)
                if num and num >= 1 and num <= 20 then
                    Config.max_agents = math.floor(num)
                    Config.save()
                    Logger.success("Max agents: " .. Config.max_agents)
                else
                    Logger.error("Must be between 1 and 20.")
                end
            elseif agentSel then
                Config.max_agents = tonumber(agentSel) or 5
                Config.save()
                Logger.success("Max agents: " .. agentSel)
            end
            Task.wait(1)
        elseif selection == "back" then
            return
        end
    end
end
    
function Wizard.start(skipWelcome: boolean?)
    if not skipWelcome then
        TUI.drawHeader("Setup Wizard")
        TUI.drawBox("Welcome", "Let's get Copal configured.\nThis will set up your AI provider, API key, and models.")
    end

    -- 1. Provider Selection
    TUI.drawHeader("Select AI Provider")
    TUI.blank()
    
    local providers = {"opencode", "openrouter", "openai", "custom"}
    local selectedProvider = TUI.menu({
        {label = "OpenCode",    value = "opencode",   description = "Default provider"},
        {label = "OpenRouter",  value = "openrouter",  description = "Multi-model gateway"},
        {label = "OpenAI",      value = "openai",      description = "GPT models"},
        {label = "Custom",      value = "custom",      description = "Self-hosted / other"},
    })
    
    if not selectedProvider then
        selectedProvider = "opencode"
    end

    Auth.setProvider(selectedProvider)
    local providerConfig = Config.providers[selectedProvider]

    if selectedProvider == "custom" then
        local url = TUI.prompt("Base URL (Default: " .. providerConfig.url .. ")")
        if #url > 0 then
            providerConfig.url = url
            Config.providers.custom.url = url
        end
    end

    -- 2. API Key
    local apiKey = ""
    local skipKeyEntry = false
    
    if providerConfig.key and #providerConfig.key > 0 then
        TUI.section("Existing Key Found")
        TUI.sectionItem("✔", "green", "An API key is already configured.")
        TUI.sectionEnd()
        
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
            
            TUI.startSpinner("Validating key...")
            local valid = Auth.validateKey(apiKey)
            TUI.stopSpinner()
            
            if valid then
                Logger.success("API Key valid!")
                providerConfig.key = apiKey
                break
            else
                Logger.error("Invalid API Key or connection failed.")
                local retry = TUI.prompt("Retry? (y/n)")
                if retry:lower() ~= "y" then
                    providerConfig.key = apiKey 
                    break
                end
            end
        end
    end

    -- 3. Model Selection
    providerConfig.models.low = selectModel("Swarm Agents (Low Cost)", providerConfig.models.low or "gpt-4o-mini", apiKey)
    providerConfig.models.medium = selectModel("Director (Coordination)", providerConfig.models.medium or "gpt-4o", apiKey)
    providerConfig.models.high = selectModel("Company CEO (High Intelligence)", providerConfig.models.high or "o1", apiKey)

    -- 4. Review & Save
    TUI.drawHeader("Review Configuration")
    
    local censoredKey = "sk-..." .. string.sub(apiKey, -4)
    if #apiKey < 10 then censoredKey = "(hidden)" end
    
    TUI.section("Summary")
    TUI.sectionItem("▸", "cyan",   "Provider:  " .. selectedProvider)
    TUI.sectionItem("▸", "yellow", "API Key:   " .. censoredKey)
    TUI.sectionItem("▸", "green",  "Low Model: " .. providerConfig.models.low)
    TUI.sectionItem("▸", "green",  "Mid Model: " .. providerConfig.models.medium)
    TUI.sectionItem("▸", "green",  "Top Model: " .. providerConfig.models.high)
    TUI.sectionEnd()
    TUI.blank()
    
    local confirm = TUI.prompt("Save configuration? (y/n)")
    if confirm:lower() == "y" then
        Config.save()
        Logger.success("Configuration saved to " .. Config.configFile)
    else
        Logger.warn("Configuration NOT saved.")
    end
end

return Wizard
