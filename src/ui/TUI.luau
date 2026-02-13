--!strict
local stdio = require("@lune/stdio")
local process = require("@lune/process")

local Monitor = require("../lib/Monitor")

local TUI = {}

local ESC = "\27"
local CLEAR_SCREEN = ESC .. "[2J"
local HOME_CURSOR = ESC .. "[H"

local hasShownSplash = false

-- Subscribe to Monitor events on load
Monitor.subscribe(function(event)
    if event.type == "log" then
        stdio.write(stdio.color("blue") .. "[" .. event.source .. "] " .. stdio.color("reset") .. tostring(event.data) .. "\n")
    elseif event.type == "thought" then
        stdio.write(stdio.color("yellow") .. "[" .. event.source .. "] " .. stdio.style("dim") .. tostring(event.data) .. stdio.style("reset") .. "\n")
    elseif event.type == "tool_call" then
        stdio.write(stdio.color("magenta") .. "[" .. event.source .. "] Calling " .. event.data.tool .. "...\n" .. stdio.color("reset"))
    elseif event.type == "tool_result" then
        -- Optional: Don't show full result to avoid clutter, or show truncated
        -- stdio.write(stdio.color("cyan") .. "[" .. event.source .. "] Result: " .. string.sub(tostring(event.data.result), 1, 50) .. "...\n" .. stdio.color("reset"))
    elseif event.type == "completion" then
        stdio.write(stdio.color("green") .. stdio.style("bold") .. "[" .. event.source .. "] Completion: \n" .. tostring(event.data) .. "\n" .. stdio.style("reset") .. stdio.color("reset"))
    end
end)

function TUI.clear()
    stdio.write(CLEAR_SCREEN)
    stdio.write(HOME_CURSOR)
end

function TUI.drawHeader(title: string)
    TUI.clear()
    
    -- Always show ASCII Art
    stdio.write(stdio.style("bold"))
    stdio.write(stdio.color("blue"))
    stdio.write([[
   ______                      __
  / ____/____   ____   ____ _ / /
 / /    / __ \ / __ \ / __ `// / 
/ /___ / /_/ // /_/ // /_/ // /  
\____/ \____// .___/ \__,_//_/   
            /_/                  
]])
    stdio.write(stdio.color("reset"))
    stdio.write(stdio.style("reset"))
    
    if title and #title > 0 then
        stdio.write("\nMode: " .. stdio.color("yellow") .. title .. stdio.color("reset") .. "\n")
        stdio.write(string.rep("-", 40) .. "\n")
    end
end

function TUI.drawBox(title: string, content: string)
    stdio.write(stdio.style("bold") .. title .. ":\n" .. stdio.style("reset"))
    stdio.write(content .. "\n\n")
end

function TUI.drawDashboard(state: {
    mode: string,
    activeAgents: number,
    completedTasks: number,
    totalTasks: number,
    agents: { {id: string, status: string, iterations: number} }
})
    TUI.clear()
    TUI.drawHeader(state.mode)
    
    stdio.write(stdio.color("green") .. stdio.style("bold") .. "PROGRESS: [" .. state.completedTasks .. "/" .. state.totalTasks .. "]\n")
    -- Draw Progress Bar
    local width = 40
    local percent = state.totalTasks > 0 and (state.completedTasks / state.totalTasks) or 0
    local filled = math.floor(percent * width)
    local bar = string.rep("█", filled) .. string.rep("░", width - filled)
    stdio.write(stdio.color("cyan") .. bar .. " " .. math.floor(percent * 100) .. "%\n" .. stdio.color("reset"))
    
    stdio.write("\n" .. stdio.style("bold") .. "AGENTS:" .. stdio.style("reset") .. "\n")
    for _, agent in ipairs(state.agents) do
        local statusColor = "white"
        if agent.status:find("Thinking") then statusColor = "yellow"
        elseif agent.status:find("Executing") then statusColor = "magenta"
        elseif agent.status:find("Error") then statusColor = "red"
        elseif agent.status:find("Done") then statusColor = "green"
        end
        
        stdio.write(agent.id .. ": " .. stdio.color(statusColor) .. agent.status .. stdio.color("reset") .. " (Iter: " .. agent.iterations .. ")\n")
    end
    
    stdio.write("\n" .. stdio.style("dim") .. "Controls: /pause, /resume, /info <msg>, /status" .. stdio.style("reset") .. "\n")
    stdio.write(string.rep("-", 40) .. "\n\n")
end

function TUI.startInputLoop(callback: (string) -> ())
    local Task = require("@lune/task")
    Task.spawn(function()
        while true do
            -- This blocks the thread, so it must be spawned.
            -- Using pcall to avoid crash on interrupt
            local success, line = pcall(function() return stdio.prompt("text", "") end)
            if success and line then
                if #line > 0 then
                    callback(line)
                end
            else
                Task.wait(0.1)
            end
        end
    end)
end

function TUI.prompt(question: string): string
    stdio.write(stdio.color("green") .. "> " .. question .. ": " .. stdio.color("reset"))
    return stdio.prompt("text", "")
end

function TUI.promptSecret(question: string): string
    stdio.write(stdio.color("green") .. "> " .. question .. ": " .. stdio.color("reset"))
    -- ANSI Hidden Mode
    stdio.write("\27[8m") 
    local input = stdio.prompt("text", "")
    -- ANSI Reset/Visible
    stdio.write("\27[28m")
    return input
end

function TUI.confirm(question: string): boolean
    stdio.write(stdio.color("yellow") .. "> " .. question .. " [y/N]: " .. stdio.color("reset"))
    local input = stdio.prompt("text", "")
    return input:lower() == "y" or input:lower() == "yes"
end

return TUI
