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

return TUI
