--!strict
local stdio = require("@lune/stdio")
local net = require("@lune/net")
local serde = require("@lune/serde")
local Logger = require("../lib/Logger")
local Config = require("../lib/Config")

local Auth = {}

function Auth.login()
    Config.load()
    local provider = Config.getActive()
    
    if provider.key and #provider.key > 0 then
        -- Validate the key to ensure it's actually working
        if Auth.validateKey(provider.key) then
            Logger.success("Authenticated with " .. Config.active_provider)
            return true
        else
            Logger.error("Authentication failed for " .. Config.active_provider)
            return false
        end
    end
    return false
end

function Auth.setProvider(id: string)
    if Config.providers[id] then
        Config.active_provider = id
        Logger.info("Switched to provider: " .. id)
    else
        Logger.error("Unknown provider: " .. id)
    end
end

function Auth.validateKey(key: string): boolean
    local provider = Config.getActive()
    -- Some providers might not have a /models endpoint or it might be protected differently
    -- But standard OpenAI compatible ones usually do.
    local url = provider.url .. "/models"
    
    local success, response = pcall(function() 
        return net.request({
            url = url,
            method = "GET",
            headers = {
                ["Authorization"] = "Bearer " .. key
            }
        })
    end)

    if not success then
        -- Clean up error message to remove stack trace if possible or just log the message
        local errMsg = tostring(response):gsub("stack traceback:.*", "")
        Logger.warn("Network check failed: " .. errMsg)
        return false
    end

    return response.ok
end

function Auth.fetchModels(key: string): {string}?
    local provider = Config.getActive()
    local success, response = pcall(function()
        return net.request({
            url = provider.url .. "/models",
            method = "GET",
            headers = {
                ["Authorization"] = "Bearer " .. key
            }
        })
    end)

    if not success or not response.ok then
        return nil
    end

    local decodeSuccess, data = pcall(function() return serde.decode("json", response.body) end)
    if decodeSuccess and data and data.data then
        local models = {}
        for _, m in ipairs(data.data) do
            table.insert(models, m.id)
        end
        return models
    end
    return nil
end

function Auth.getToken(): string?
    return Config.getActive().key
end

return Auth
