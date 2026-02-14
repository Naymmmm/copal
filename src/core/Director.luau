--!strict
local Config = require("../lib/Config")
local Logger = require("../lib/Logger")
local Monitor = require("../lib/Monitor")
local LLMClient = require("../models/LLMClient")
local Swarm = require("./Swarm")
local serde = require("@lune/serde")

local Director = {}
Director.__index = Director

export type DirectorInstance = typeof(setmetatable({} :: {
    _model: string,
    _swarm: any, -- SwarmInstance
}, Director))

function Director.new(): DirectorInstance
    local self = setmetatable({}, Director)
    self._model = Config.getActive().models.medium
    self._swarm = Swarm.new(5)
    return self
end

function Director:planAndExecute(goal: string, context: string?)
    Logger.info("Director planning for goal: " .. goal)
    Monitor.log("Director", "Planning for goal: " .. goal)
    
    -- 1. Decompose goal
    local contentMsg = [[You are a Technical Director. Break down the user's goal into a JSON list of actionable subtasks.

CRITICAL RULES FOR TASK DECOMPOSITION:
- Keep the number of tasks PROPORTIONAL to the goal's complexity.
- Simple goals (e.g. "make a hello world script") = 1-3 tasks MAX.
- Medium goals (e.g. "build a REST API") = 3-5 tasks.
- Complex goals (e.g. "build a full web app") = 5-8 tasks MAX.
- Really Complex (e.g. "Make a game engine") = Unlimited
- NEVER exceed 8 tasks. Consolidate related steps into single tasks.
- Each task should be a meaningful unit of work, NOT a single line of code.
- BAD: "Create file main.py", "Add print statement", "Save file" (3 tasks for 1 thing)
- GOOD: "Create main.py with a hello world program" (1 task)

Return ONLY the JSON array of strings, no explanation.]]
    if context then
        contentMsg = contentMsg .. "\n\nOverall Mission Context: " .. context
    end
    
    local planningPrompt = {
        {role = "system", content = contentMsg},
        {role = "user", content = goal}
    }
    
    Monitor.thought("Director", "Decomposing goal into subtasks...")
    local planJson, _ = LLMClient.completion(planningPrompt, self._model, nil, nil)
    if not planJson then
        Logger.error("Director failed to create a plan.")
        Monitor.log("Director", "Failed to create plan.")
        return
    end

    -- Attempt to parse JSON
    -- Remove markdown code blocks if present
    local cleanJson = planJson:gsub("```json", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    
    local success, subTasks = pcall(function()
        return serde.decode("json", cleanJson)
    end)

    if not success or type(subTasks) ~= "table" then
        Logger.error("Failed to parse plan JSON: " .. tostring(subTasks))
        Monitor.log("Director", "Failed to parse plan JSON.")
        return
    end

    -- Sanitize tasks: ensure they are strings
    local sanitizedTasks = {}
    for _, t in ipairs(subTasks) do
        if type(t) == "string" then
            table.insert(sanitizedTasks, t)
        elseif type(t) == "table" then
            -- Try to find a logical string field
            if t.task then table.insert(sanitizedTasks, t.task)
            elseif t.description then table.insert(sanitizedTasks, t.description)
            elseif t.instruction then table.insert(sanitizedTasks, t.instruction)
            else 
                -- Fallback to JSON representation if strict string not found
                table.insert(sanitizedTasks, serde.encode("json", t)) 
            end
        else
            table.insert(sanitizedTasks, tostring(t))
        end
    end
    subTasks = sanitizedTasks
    
    -- Format Plan as Markdown for Logs
    local planMd = "## Execution Plan for: " .. goal .. "\n"
    for i, task in ipairs(subTasks) do
        planMd = planMd .. i .. ". " .. task .. "\n"
    end
    
    Logger.success("Director created plan with " .. #subTasks .. " tasks.")
    Monitor.log("Director", "Plan created with " .. #subTasks .. " tasks.")
    
    -- Render the plan through TUI
    local TUI = require("../ui/TUI")
    TUI.renderMarkdown(planMd)
    
    Monitor.log("Director", "Dispatching to Swarm.")
    
    -- 2. Execute via Swarm with Review Loop
    local maxReviews = 3
    local reviews = 0
    local results = {}
    local currentSubTasks = subTasks
    
    while reviews < maxReviews do
        Logger.info("Director executing batch (Review Cycle: " .. reviews .. ")")
        Monitor.log("Director", "Executing batch (Review Cycle: " .. reviews .. ")")
        
        results = self._swarm:execute(currentSubTasks)
        
        -- 3. Review/Aggregate
        Logger.info("Director reviewing results...")
        Monitor.log("Director", "Reviewing results...")
        
        local reviewPrompt = {
            {role = "system", content = "You are a Technical Director. Review the results of the subtasks. If they are satisfactory and the original goal is met, return 'SUCCESS'. If not, return a JSON list of NEW subtasks to fix the issues. Do not return the original tasks if they failed, provide adjusted tasks."},
            {role = "user", content = "Original Goal: " .. goal .. "\n\nResults:\n" .. serde.encode("json", results)}
        }
        
        Monitor.thought("Director", "Analyzing results and deciding next steps...")
        local reviewOutput, _ = LLMClient.completion(reviewPrompt, self._model, nil, nil)
        
        if reviewOutput then
            if reviewOutput:find("SUCCESS") then
                Logger.success("Director is satisfied with result.")
                Monitor.log("Director", "Goal achieved.")
                break
            else
                -- Try to parse new tasks
                local cleanReview = reviewOutput:gsub("```json", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local success, newTasks = pcall(function() return serde.decode("json", cleanReview) end)
                
                if success and type(newTasks) == "table" and #newTasks > 0 then
                    -- Sanitize newTasks
                    local sanitizedNewTasks = {}
                    for _, t in ipairs(newTasks) do
                        if type(t) == "string" then
                            table.insert(sanitizedNewTasks, t)
                        elseif type(t) == "table" then
                            if t.description then table.insert(sanitizedNewTasks, t.description)
                            elseif t.task then table.insert(sanitizedNewTasks, t.task)
                            else table.insert(sanitizedNewTasks, serde.encode("json", t)) end
                        else
                            table.insert(sanitizedNewTasks, tostring(t))
                        end
                    end
                    newTasks = sanitizedNewTasks
                    Logger.warn("Director requested revisions: " .. #newTasks .. " new tasks.")
                    Monitor.log("Director", "Revisions needed. Spawning " .. #newTasks .. " fix tasks.")
                    currentSubTasks = newTasks
                    reviews += 1
                else
                    Logger.warn("Director provided feedback but no valid JSON tasks. Assuming success or manual intervention needed.")
                    Monitor.log("Director", "Feedback provided but no new tasks generated.")
                    break
                end
            end
        else
            Logger.error("Director failed to review.")
            break
        end
    end
    
    return results
end

return Director
