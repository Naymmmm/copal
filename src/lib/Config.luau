--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local process = require("@lune/process")

local function getHomeDir(): string?
    local env = process.env
    if process.os == "windows" then
        return env.USERPROFILE
    else
        return env.HOME
    end
end

local HOME_DIR = getHomeDir()
local CONFIG_FILE = (HOME_DIR and (HOME_DIR .. "/.copal_config.json")) or "copal_config.json"

export type ProviderConfig = {
    url: string,
    key: string,
    models: {
        low: string,
        medium: string,
        high: string,
        search: string
    }
}

local Config = {
    configFile = CONFIG_FILE,
    active_provider = "opencode",
    security_level = "restricted", -- "restricted" | "full_access"
    shell_preference = "auto", -- "auto" | "pwsh" | "powershell" | "bash" | "cmd"
    rate_limit_delay = 0, -- seconds to wait between LLM calls (0 = no delay)
    max_agents = 5, -- max concurrent agents in swarm mode
    providers = {
        opencode = {
            url = "https://api.opencode.com/v1",
            key = "",
            models = {low = "gpt-4o-mini", medium = "gpt-4o", high = "o1", search = "perplexity/sonar-reasoning"}
        } :: ProviderConfig,
        openrouter = {
            url = "https://openrouter.ai/api/v1",
            key = "",
            models = {low = "liquid/lfm-40b", medium = "anthropic/claude-3.5-sonnet", high = "openai/o1-preview", search = "x-ai/grok-4.1-fast"}
        } :: ProviderConfig,
        openai = {
            url = "https://api.openai.com/v1",
            key = "",
            models = {low = "gpt-4o-mini", medium = "gpt-4o", high = "o1-preview", search = "gpt-4o"}
        } :: ProviderConfig,
        custom = {
            url = "http://localhost:11434/v1",
            key = "sk-proj-custom",
            models = {low = "llama3", medium = "llama3", high = "llama3", search = "llama3"}
        } :: ProviderConfig
    }
}

function Config.load()
    if fs.isFile(CONFIG_FILE) then
        local content = fs.readFile(CONFIG_FILE)
        local success, data = pcall(function() return serde.decode("json", content) end)
        if success and type(data) == "table" then
            if data.active_provider then Config.active_provider = data.active_provider end
            if data.security_level then Config.security_level = data.security_level end
            if data.shell_preference then Config.shell_preference = data.shell_preference end
            if data.rate_limit_delay then Config.rate_limit_delay = tonumber(data.rate_limit_delay) or 0 end
            if data.max_agents then Config.max_agents = tonumber(data.max_agents) or 5 end
            if data.providers then 
                for k, v in pairs(data.providers) do
                    Config.providers[k] = v
                end
            end
            return true
        end
    end
    return false
end

function Config.save()
    local content = serde.encode("json", {
        active_provider = Config.active_provider,
        security_level = Config.security_level,
        shell_preference = Config.shell_preference,
        rate_limit_delay = Config.rate_limit_delay,
        max_agents = Config.max_agents,
        providers = Config.providers
    }, true)
    fs.writeFile(CONFIG_FILE, content)
end

function Config.exists()
    return fs.isFile(CONFIG_FILE)
end

function Config.getActive(): ProviderConfig
    return Config.providers[Config.active_provider] or Config.providers.opencode
end

return Config
