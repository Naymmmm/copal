--!strict
local Swarm = require("../src/core/Swarm")
local LLMClient = require("../src/models/LLMClient")
local Logger = require("../src/lib/Logger")
local Auth = require("../src/core/Auth")

-- Mock Auth
function Auth.getToken()
    return "test-token"
end

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

-- Mock LLMClient
function LLMClient.completion(messages, model, tools)
    Logger.info("Mock LLM called with model: " .. model)
    return "Mocked response for task"
end

Logger.info("Starting Swarm Test...")

local swarm = Swarm.new(3)
local tasks = {"Task A", "Task B", "Task C"}

local results = swarm:execute(tasks)

for _, res in ipairs(results) do
    if res.status == "success" and res.output == "Mocked response for task" then
        Logger.success("Task " .. res.task .. " Passed")
    else
        Logger.error("Task " .. res.task .. " Failed")
    end
end
