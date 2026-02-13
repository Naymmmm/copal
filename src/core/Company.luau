--!strict
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local Monitor = require("../lib/Monitor")
local LLMClient = require("../models/LLMClient")
local Director = require("./Director")
local serde = require("@lune/serde")
local Task = require("@lune/task")

local Company = {}
Company.__index = Company

export type CompanyInstance = typeof(setmetatable({} :: {
    _model: string,
    _directors: {any} -- List of DirectorInstance
}, Company))

function Company.new(): CompanyInstance
    local self = setmetatable({}, Company)
    self._model = Config.getActive().models.high -- CEO uses high-end model
    self._directors = {}
    return self
end

function Company:start(mission: string)
    Logger.info("Company CEO started. Mission: " .. mission)
    Monitor.log("CEO", "Started. Mission: " .. mission)
    
    -- 1. Create Strategic Plan (Departments/Directives)
    local strategyPrompt = {
        {role = "system", content = "You are the CEO of a software company. Given the mission, create a strategy consisting of 2-4 high-level directives (departments). Return ONLY a JSON list of strings, where each string is a directive for a Director."},
        {role = "user", content = mission}
    }
    
    Monitor.thought("CEO", "Formulating strategy...")
    local strategyJson, _ = LLMClient.completion(strategyPrompt, self._model, nil, nil)
    if not strategyJson then
        Logger.error("CEO failed to formulate strategy.")
        Monitor.log("CEO", "Failed to formulate strategy.")
        return
    end
    
    local cleanJson = strategyJson:gsub("```json", ""):gsub("```", "")
    local success, directives = pcall(function()
        return serde.decode("json", cleanJson)
    end)
    
    if not success or type(directives) ~= "table" then
        Logger.error("Failed to parse strategy JSON.")
        Monitor.log("CEO", "Failed to parse strategy JSON.")
        return
    end
    
    Logger.success("CEO established " .. #directives .. " directives.")
    Monitor.log("CEO", "Established " .. #directives .. " directives. Hiring Directors...")
    
    -- 2. Spawn Directors for each directive
    local directiveResults = {}
    local pending = #directives
    
    for i, directive in ipairs(directives) do
        Task.spawn(function()
            Logger.info("Spawning Director " .. i .. " for: " .. directive)
            Monitor.log("CEO", "Spawning Director " .. i .. " for: " .. directive)
            local director = Director.new()
            table.insert(self._directors, director)
            
            local results = director:planAndExecute(directive)
            directiveResults[directive] = results
            pending -= 1
        end)
    end
    
    -- Wait for all directors (parallel departmental work)
    while pending > 0 do
        Task.wait(0.5)
    end
    
    Logger.success("All departments reported back. Mission Complete.")
    Monitor.log("CEO", "All departments finished. Mission Complete.")
    return directiveResults
end

return Company
