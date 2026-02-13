--!strict
local Director = require("../src/core/Director")
local LLMClient = require("../src/models/LLMClient")
local Logger = require("../src/lib/Logger")
local Auth = require("../src/core/Auth")

local Config = require("../src/lib/Config")

-- Mock Config
function Config.getActive()
    return {
        models = {
            low = "test-low",
            medium = "test-medium",
            high = "test-high"
        }
    }
end

-- Mock Auth
function Auth.getToken() return "test-token" end

-- Mock LLMClient
function LLMClient.completion(messages, model, tools)
    Logger.info("Mock LLM called with model: '" .. tostring(model) .. "'")
    if model and (model:find("gpt%-4o") or model == "test-medium") then
        -- Director planning
        return '["Task 1", "Task 2"]'
    else
        -- Swarm execution
        return '["Fallback Task"]'
    end
end

Logger.info("Starting Director Test...")

local director = Director.new()
local results = director:planAndExecute("Test Goal")

if results and #results == 2 then
    Logger.success("Director Test Passed")
else
    Logger.error("Director Test Failed")
end
