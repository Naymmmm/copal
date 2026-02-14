--!strict
local stdio = require("@lune/stdio")
local process = require("@lune/process")
local Task = require("@lune/task")

local Monitor = require("../lib/Monitor")
local Config = require("../lib/Config")

local TUI = {}

local ESC = "\27"
local CLEAR_SCREEN = ESC .. "[2J"
local HOME_CURSOR = ESC .. "[H"
local HIDE_CURSOR = ESC .. "[?25l"
local SHOW_CURSOR = ESC .. "[?25h"

-- ═══════════════════════════════════════
--  Global State
-- ═══════════════════════════════════════
TUI._stdinLocked = false
TUI._compact = false
TUI._currentMode = "idle"        -- "idle", "swarm", "director", "company"
TUI._spinnerActive = false
TUI._spinnerThread = nil

-- ═══════════════════════════════════════
--  Theme / Constants
-- ═══════════════════════════════════════
local THEME = {
    border   = "cyan",
    accent   = "blue",
    success  = "green",
    warning  = "yellow",
    error    = "red",
    muted    = "white",    -- used with dim style
    info     = "cyan",
    agent    = "magenta",
}

local ICONS = {
    success  = "",   -- nf-fa-check_circle
    error    = "",   -- nf-fa-times_circle
    warning  = "",   -- nf-fa-exclamation_triangle
    info     = "",   -- nf-cod-info
    arrow    = "",   -- nf-cod-arrow_right
    thinking = "",   -- nf-fa-brain
    tool     = "",   -- nf-fa-wrench
    agent    = "",   -- nf-oct-person
    prompt   = "",   -- nf-cod-chevron_right
    divider  = "─",
    broadcast = "", -- nf-fa-bullhorn
    whisper  = "",   -- nf-fa-comment
    help     = "",   -- nf-fa-question_circle
    progress = "",   -- nf-fa-tasks
    model    = "",   -- nf-fa-microchip
    lock     = "",   -- nf-fa-lock
    unlock   = "",   -- nf-fa-unlock
    stats    = "",   -- nf-fa-bar_chart
}

local SPINNER_FRAMES = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

-- ═══════════════════════════════════════
--  Slash Command Registry
-- ═══════════════════════════════════════
export type SlashCommand = {
    name: string,
    description: string,
    usage: string,
    handler: (args: string?) -> ()
}

local slashCommands: {[string]: SlashCommand} = {}

function TUI.registerCommand(cmd: SlashCommand)
    slashCommands[cmd.name] = cmd
end

function TUI.getCommand(name: string): SlashCommand?
    return slashCommands[name]
end

function TUI.getAllCommands(): {[string]: SlashCommand}
    return slashCommands
end

-- ═══════════════════════════════════════
--  Drawing Primitives
-- ═══════════════════════════════════════

function TUI.clear()
    stdio.write(CLEAR_SCREEN)
    stdio.write(HOME_CURSOR)
end

local function w(text: string)
    stdio.write(text)
end

local function wColor(color: string, text: string)
    w(stdio.color(color) .. text .. stdio.color("reset"))
end

local RESET_ALL = "\27[0m"

local function wBold(text: string)
    w(stdio.style("bold") .. text .. RESET_ALL)
end

local function wDim(text: string)
    w(stdio.style("dim") .. text .. RESET_ALL)
end

local function wBoldColor(color: string, text: string)
    w(stdio.style("bold") .. stdio.color(color) .. text .. RESET_ALL)
end

function TUI.divider(width: number?)
    local len = width or 50
    wDim(string.rep(ICONS.divider, len) .. "\n")
end

function TUI.blank()
    w("\n")
end

-- ═══════════════════════════════════════
--  Header / Branding
-- ═══════════════════════════════════════

local fs = require("@lune/fs")

local VERSION = (function()
    local ok, content = pcall(function() return fs.readFile("pesde.toml") end)
    if ok then
        local ver = content:match('version%s*=%s*"([^"]+)"')
        if ver then return ver end
    end
    return "0.2.11"
end)()

function TUI.drawHeader(title: string?)
    TUI.clear()
    
    wBoldColor(THEME.accent, [[
   ______                      __
  / ____/____   ____   ____ _ / /
 / /    / __ \ / __ \ / __ `// / 
/ /___ / /_/ // /_/ // /_/ // /  
\____/ \____// .___/ \__,_//_/   
            /_/                  
]])
    wDim("  v" .. VERSION .. "\n")
    
    if title and #title > 0 then
        wBold("  Mode: ")
        wBoldColor(THEME.warning, title)
        w("\n")
        w("  ")
        TUI.divider(48)
    end
end

-- ═══════════════════════════════════════
--  Sections & Boxes
-- ═══════════════════════════════════════

function TUI.section(title: string)
    TUI.blank()
    wBoldColor(THEME.border, "┌─ ")
    wBold(title)
    wBoldColor(THEME.border, " " .. string.rep("─", math.max(0, 44 - #title)))
    w("\n")
end

function TUI.sectionEnd()
    wBoldColor(THEME.border, "└" .. string.rep("─", 50))
    w("\n")
end

function TUI.sectionItem(icon: string, color: string, text: string)
    wColor(THEME.border, "│ ")
    wColor(color, icon .. " ")
    w(text .. "\n")
end

function TUI.drawBox(title: string, content: string)
    TUI.section(title)
    for line in content:gmatch("[^\n]+") do
        TUI.sectionItem(ICONS.info, THEME.info, line)
    end
    TUI.sectionEnd()
end

-- ═══════════════════════════════════════
--  Spinner
-- ═══════════════════════════════════════

function TUI.startSpinner(label: string)
    TUI._spinnerActive = true
    TUI._spinnerThread = Task.spawn(function()
        local frameIdx = 1
        while TUI._spinnerActive do
            local frame = SPINNER_FRAMES[frameIdx]
            stdio.write("\r" .. stdio.color(THEME.info) .. frame .. " " .. stdio.color("reset") .. label .. "  ")
            frameIdx = (frameIdx % #SPINNER_FRAMES) + 1
            Task.wait(0.08)
        end
        stdio.write("\r" .. string.rep(" ", #label + 10) .. "\r") -- clear line
    end)
end

function TUI.stopSpinner()
    TUI._spinnerActive = false
    Task.wait(0.15) -- let the spinner thread finish
end

-- ═══════════════════════════════════════
--  Dashboard (Agent Status)
-- ═══════════════════════════════════════

function TUI.drawDashboard(state: {
    mode: string,
    activeAgents: number,
    completedTasks: number,
    totalTasks: number,
    agents: { {id: string, status: string, iterations: number} }
})
    TUI.drawHeader(state.mode)
    
    -- Progress Bar
    TUI.section("Progress")
    local width = 30
    local percent = state.totalTasks > 0 and (state.completedTasks / state.totalTasks) or 0
    local filled = math.floor(percent * width)
    local bar = string.rep("█", filled) .. string.rep("░", width - filled)
    TUI.sectionItem("", THEME.success, bar .. "  " .. state.completedTasks .. "/" .. state.totalTasks .. " (" .. math.floor(percent * 100) .. "%)")
    TUI.sectionEnd()
    
    -- Agent Status
    TUI.section("Agents")
    for _, agent in ipairs(state.agents) do
        local statusColor = THEME.muted
        local icon = ICONS.agent
        if agent.status:find("Thinking") then statusColor = THEME.warning; icon = ICONS.thinking
        elseif agent.status:find("Executing") then statusColor = THEME.agent; icon = ICONS.tool
        elseif agent.status:find("Error") then statusColor = THEME.error; icon = ICONS.error
        elseif agent.status:find("Done") or agent.status:find("Success") then statusColor = THEME.success; icon = ICONS.success
        elseif agent.status:find("Waiting") or agent.status:find("Asking") then statusColor = THEME.info; icon = ICONS.warning
        elseif agent.status:find("Paused") then statusColor = THEME.accent; icon = ICONS.info
        end
        
        TUI.sectionItem(icon, statusColor, agent.id .. ": " .. stdio.color(statusColor) .. agent.status .. stdio.color("reset") .. stdio.style("dim") .. " (iter " .. agent.iterations .. ")" .. stdio.style("reset"))
    end
    TUI.sectionEnd()
    
    TUI.blank()
    wDim("  Type /help for available commands\n")
end

-- ═══════════════════════════════════════
--  Monitor Event Rendering
-- ═══════════════════════════════════════

Monitor.subscribe(function(event)
    if TUI._stdinLocked then return end
    
    if TUI._compact then
        if event.type == "completion" then
            wBoldColor(THEME.success, ICONS.success .. " [" .. event.source .. "] ")
            w(tostring(event.data) .. RESET_ALL .. "\n")
        end
        return
    end
    
    if event.type == "log" then
        wColor(THEME.info, ICONS.info .. " ")
        wBold("[" .. event.source .. "] ")
        w(tostring(event.data) .. RESET_ALL .. "\n")
    elseif event.type == "thought" then
        wColor(THEME.warning, ICONS.thinking .. " ")
        wDim("[" .. event.source .. "] " .. tostring(event.data))
        w(RESET_ALL .. "\n")
    elseif event.type == "tool_call" then
        wColor(THEME.agent, ICONS.tool .. " ")
        wBold("[" .. event.source .. "] ")
        w("→ " .. event.data.tool)
        
        -- Show contextual detail based on tool type
        local detail = nil
        local ok, parsed = pcall(function() 
            return require("@lune/serde").decode("json", event.data.args or "{}") 
        end)
        if ok and parsed then
            if parsed.source and parsed.destination then
                detail = parsed.source .. " → " .. parsed.destination
            elseif parsed.path then
                detail = parsed.path
            elseif parsed.command then
                local cmd = tostring(parsed.command)
                if parsed.args then
                    if type(parsed.args) == "table" then
                        cmd = cmd .. " " .. table.concat(parsed.args, " ")
                    elseif type(parsed.args) == "string" then
                        cmd = cmd .. " " .. parsed.args
                    end
                end
                -- Truncate long commands
                if #cmd > 60 then cmd = cmd:sub(1, 57) .. "..." end
                detail = cmd
            elseif parsed.target then
                detail = parsed.target .. (parsed.reason and (" — " .. parsed.reason) or "")
            elseif parsed.message then
                local msg = tostring(parsed.message)
                if #msg > 50 then msg = msg:sub(1, 47) .. "..." end
                detail = msg
            elseif parsed.url then
                detail = parsed.url
            elseif parsed.question then
                local q = tostring(parsed.question)
                if #q > 50 then q = q:sub(1, 47) .. "..." end
                detail = q
            elseif parsed.seconds then
                detail = parsed.seconds .. "s" .. (parsed.reason and (" — " .. parsed.reason) or "")
            end
        end
        
        if detail then
            wDim("  " .. detail)
        end
        w(RESET_ALL .. "\n")
    elseif event.type == "tool_result" then
        -- Suppressed for cleanliness
    elseif event.type == "completion" then
        TUI.blank()
        TUI.section(event.source .. " Result")
        for line in tostring(event.data):gmatch("[^\n]+") do
            TUI.sectionItem("", THEME.success, line)
        end
        TUI.sectionEnd()
    end
end)

-- ═══════════════════════════════════════
--  Command Help Display
-- ═══════════════════════════════════════

local function showCommandHelp()
    TUI.blank()
    TUI.section("Available Commands")
    
    -- Collect and sort command names
    local names = {}
    for name in pairs(slashCommands) do
        table.insert(names, name)
    end
    table.sort(names)
    
    for _, name in ipairs(names) do
        local cmd = slashCommands[name]
        wColor(THEME.border, "│ ")
        wBoldColor(THEME.info, "  /" .. cmd.name)
        local pad = string.rep(" ", math.max(1, 14 - #cmd.name))
        w(pad)
        wDim(cmd.description)
        w("\n")
        if cmd.usage and #cmd.usage > 0 then
            wColor(THEME.border, "│ ")
            w("  " .. string.rep(" ", 14))
            wDim("Usage: /" .. cmd.usage)
            w("\n")
        end
    end
    TUI.sectionEnd()
    TUI.blank()
end

-- ═══════════════════════════════════════
--  Register Built-in Commands
-- ═══════════════════════════════════════

TUI.registerCommand({
    name = "help",
    description = "Show all available commands",
    usage = "help",
    handler = function() showCommandHelp() end,
})

TUI.registerCommand({
    name = "clear",
    description = "Clear the screen",
    usage = "clear",
    handler = function() TUI.clear() end,
})

TUI.registerCommand({
    name = "compact",
    description = "Toggle compact output (less noise)",
    usage = "compact",
    handler = function()
        TUI._compact = not TUI._compact
        if TUI._compact then
            wBoldColor(THEME.success, ICONS.success .. " Compact mode ON\n")
        else
            wBoldColor(THEME.success, ICONS.success .. " Compact mode OFF\n")
        end
    end,
})

TUI.registerCommand({
    name = "model",
    description = "Show current model configuration",
    usage = "model",
    handler = function()
        local provider = Config.getActive()
        TUI.section("Model Configuration")
        TUI.sectionItem(ICONS.info, THEME.info, "Provider: " .. (Config.active_provider or "unknown"))
        TUI.sectionItem(ICONS.agent, THEME.warning, "Swarm:    " .. (provider.models.low or "unset"))
        TUI.sectionItem(ICONS.agent, THEME.warning, "Director: " .. (provider.models.medium or "unset"))
        TUI.sectionItem(ICONS.agent, THEME.warning, "CEO:      " .. (provider.models.high or "unset"))
        TUI.sectionEnd()
    end,
})

TUI.registerCommand({
    name = "security",
    description = "Show current security level",
    usage = "security",
    handler = function()
        local level = Config.security_level or "restricted"
        local icon = level == "restricted" and ICONS.lock or ICONS.unlock
        local color = level == "restricted" and THEME.warning or THEME.success
        wColor(color, icon .. " Security: " .. level .. "\n")
    end,
})

TUI.registerCommand({
    name = "usage",
    description = "Show LLM token usage statistics",
    usage = "usage",
    handler = function()
        local LLMClient = require("../models/LLMClient")
        local u = LLMClient.getUsage()
        TUI.section(ICONS.stats .. " Token Usage")
        TUI.sectionItem(ICONS.info, THEME.info, "Requests:     " .. u.requests)
        TUI.sectionItem(ICONS.arrow, THEME.muted, "Prompt Tokens: " .. u.promptTokens)
        TUI.sectionItem(ICONS.arrow, THEME.muted, "Comp. Tokens:  " .. u.completionTokens)
        TUI.sectionItem(ICONS.stats, THEME.success, "Total Tokens:  " .. u.totalTokens)
        TUI.sectionItem(ICONS.thinking, THEME.warning, "Avg Latency:   " .. u.avgLatencyMs .. "ms")
        TUI.sectionItem(ICONS.error, THEME.error, "Errors:        " .. u.errors)
        TUI.sectionEnd()
    end,
})

-- /pause, /resume, /status, /info are registered dynamically by Swarm when active

-- ═══════════════════════════════════════
--  Input Loop & Command Dispatch
-- ═══════════════════════════════════════

-- Dispatch a slash command. Returns true if a command was handled.
function TUI.dispatchCommand(input: string): boolean
    if input:sub(1, 1) ~= "/" then return false end
    
    local cmdName = input:match("^/(%S+)")
    local cmdArgs = input:match("^/%S+%s+(.*)")
    
    if not cmdName then return false end
    
    local cmd = slashCommands[cmdName]
    if cmd then
        cmd.handler(cmdArgs)
        return true
    else
        wColor(THEME.error, ICONS.error .. " Unknown command: /" .. cmdName .. ". Type /help for available commands.\n")
        return true
    end
end

-- Store callback for non-command input — NO background stdio.prompt
-- The old version spawned a background prompt that competed for stdin,
-- causing garbled input on Windows. Now commands are dispatched inline.
TUI._inputCallback = nil :: ((string) -> ())?

-- Input loop removed as per user request to fix stdin corruption.
-- We no longer spawn a background task to listen for commands.
function TUI.startInputLoop(callback: (string) -> ())
    -- No-op
end

-- ═══════════════════════════════════════
--  Prompts (with stdin lock)
-- ═══════════════════════════════════════

function TUI.prompt(question: string): string
    wColor(THEME.success, ICONS.prompt .. " ")
    wBold(question .. ": ")
    return stdio.prompt("text", "") or ""
end

function TUI.promptSecret(question: string): string
    wColor(THEME.success, ICONS.prompt .. " ")
    wBold(question .. ": ")
    w("\27[8m")
    local input = stdio.prompt("text", "")
    w("\27[28m")
    return input
end

function TUI.confirm(question: string): boolean
    TUI.blank()
    TUI.section("Approval Required")
    for line in question:gmatch("[^\n]+") do
        TUI.sectionItem(ICONS.warning, THEME.warning, line)
    end
    TUI.sectionEnd()
    
    local result = stdio.prompt("confirm", question)
    return result
end

function TUI.askUser(question: string): string
    TUI.blank()
    TUI.section("Agent Question")
    for line in question:gmatch("[^\n]+") do
        TUI.sectionItem(ICONS.info, THEME.info, line)
    end
    wColor(THEME.border, "│\n")
    wColor(THEME.border, "│ ")
    wBoldColor(THEME.success, "  " .. ICONS.prompt .. " ")
    
    local input = stdio.prompt("text", "")
    TUI.sectionEnd()
    
    return input
end

-- ═══════════════════════════════════════
--  Markdown-lite Rendering
-- ═══════════════════════════════════════

function TUI.renderMarkdown(text: string)
    local lastWasBlank = false
    for line in text:gmatch("[^\n]*") do
        if line:match("^## ") then
            TUI.blank()
            wBoldColor(THEME.accent, "  " .. line:sub(4))
            w("\n")
            w("  ")
            TUI.divider(#line)
            lastWasBlank = false
        elseif line:match("^# ") then
            TUI.blank()
            wBoldColor(THEME.warning, "  " .. line:sub(3))
            w("\n")
            w("  ")
            TUI.divider(#line + 4)
            lastWasBlank = false
        elseif line:match("^%d+%. ") then
            local num, rest = line:match("^(%d+)%. (.*)")
            wColor(THEME.info, "  " .. num .. ". ")
            w(rest .. RESET_ALL .. "\n")
            lastWasBlank = false
        elseif line:match("^%- ") then
            wColor(THEME.info, "  • ")
            w(line:sub(3) .. RESET_ALL .. "\n")
            lastWasBlank = false
        elseif line:match("^```") then
            wDim("  " .. string.rep("─", 40) .. "\n")
            lastWasBlank = false
        elseif #line == 0 then
            -- Collapse consecutive blank lines into one
            if not lastWasBlank then
                w("\n")
            end
            lastWasBlank = true
        else
            w("  " .. line .. "\n")
            lastWasBlank = false
        end
    end
end

-- ═══════════════════════════════════════
--  Menu Selection Helper
-- ═══════════════════════════════════════

function TUI.menu(options: {{label: string, value: string, description: string?}}): string?
    for i, opt in ipairs(options) do
        wColor(THEME.info, "  " .. i .. ". ")
        wBold(opt.label)
        if opt.description then
            wDim("  " .. opt.description)
        end
        w("\n")
    end
    TUI.blank()
    
    local sel = TUI.prompt("Select (1-" .. #options .. ")")
    local idx = tonumber(sel)
    if idx and idx >= 1 and idx <= #options then
        return options[idx].value
    end
    return nil
end

return TUI
