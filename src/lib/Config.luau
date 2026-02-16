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
        search: string,
        embedding: string
    }
}

local Config = {
    configFile = CONFIG_FILE,
    active_provider = "opencode",
    security_level = "restricted", -- "restricted" | "full_access"
    shell_preference = "auto", -- "auto" | "pwsh" | "powershell" | "bash" | "cmd"
    rate_limit_delay = 0, -- seconds to wait between LLM calls (0 = no delay)
    max_agents = 5, -- max concurrent agents in swarm mode
    max_director_iterations = 3, -- max review cycles for director
    max_swarm_iterations = 10, -- max tool calls for swarm agents
    memory_max_items = 500, -- max memories before pruning oldest
    memory_relevance_threshold = 0.4, -- minimum cosine similarity for search results
    providers = {
        opencode = {
            url = "https://api.opencode.com/v1",
            key = "",
            models = {low = "gpt-4o-mini", medium = "gpt-4o", high = "o1", search = "perplexity/sonar-reasoning", embedding = "text-embedding-3-small"}
        } :: ProviderConfig,
        openrouter = {
            url = "https://openrouter.ai/api/v1",
            key = "",
            models = {low = "liquid/lfm-40b", medium = "anthropic/claude-3.5-sonnet", high = "openai/o1-preview", search = "perplexity/sonar", embedding = "text-embedding-3-small"}
        } :: ProviderConfig,
        openai = {
            url = "https://api.openai.com/v1",
            key = "",
            models = {low = "gpt-4o-mini", medium = "gpt-4o", high = "o1-preview", search = "gpt-4o", embedding = "text-embedding-3-small"}
        } :: ProviderConfig,
        custom = {
            url = "http://localhost:11434/v1",
            key = "sk-proj-custom",
            models = {low = "llama3", medium = "llama3", high = "llama3", search = "llama3", embedding = "nomic-embed-text"}
        } :: ProviderConfig
    },
    mcpServers = {
        -- Example:
        -- filesystem = { command = "npx", args = {"-y", "@modelcontextprotocol/server-filesystem", "."} }
    } :: {[string]: {command: string, args: {string}}}
}

function Config.load()
    local configPath = Config.configFile
    if fs.isFile(configPath) then
        local content = fs.readFile(configPath)
        local success, data = pcall(function() return serde.decode("json", content) end)
        if success and type(data) == "table" then
            if data.active_provider then Config.active_provider = data.active_provider end
            if data.security_level then Config.security_level = data.security_level end
            if data.shell_preference then Config.shell_preference = data.shell_preference end
            if data.rate_limit_delay then Config.rate_limit_delay = tonumber(data.rate_limit_delay) or 0 end
            if data.max_agents then Config.max_agents = tonumber(data.max_agents) or 5 end
            if data.max_director_iterations then Config.max_director_iterations = tonumber(data.max_director_iterations) or 3 end
            if data.max_swarm_iterations then Config.max_swarm_iterations = tonumber(data.max_swarm_iterations) or 10 end
            if data.memory_max_items then Config.memory_max_items = tonumber(data.memory_max_items) or 500 end
            if data.memory_relevance_threshold then Config.memory_relevance_threshold = tonumber(data.memory_relevance_threshold) or 0.4 end
            if data.providers then 
                for k, v in pairs(data.providers) do
                    -- Deep merge or just ensure search exists?
                    -- Simple approach: If provider exists in defaults, use default as base and verify
                    local defaultProvider = Config.providers[k]
                    if defaultProvider then
                        -- Merge models: saved values override defaults
                        if v.models then
                            for modelKey, modelVal in pairs(v.models) do
                                defaultProvider.models[modelKey] = modelVal
                            end
                        end
                        if v.url then defaultProvider.url = v.url end
                        if v.key then defaultProvider.key = v.key end
                    else
                        -- Custom provider, take as is
                        Config.providers[k] = v
                    end
                end
            end
            if data.mcpServers then
                 Config.mcpServers = data.mcpServers
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
        max_director_iterations = Config.max_director_iterations,
        max_swarm_iterations = Config.max_swarm_iterations,
        memory_max_items = Config.memory_max_items,
        memory_relevance_threshold = Config.memory_relevance_threshold,
        providers = Config.providers,
        mcpServers = Config.mcpServers
    }, true)
    fs.writeFile(Config.configFile, content)
end

function Config.exists()
    return fs.isFile(Config.configFile)
end

function Config.getActive(): ProviderConfig
    return Config.providers[Config.active_provider] or Config.providers.opencode
end

return Config
