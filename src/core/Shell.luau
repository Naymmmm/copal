--!strict
local process = require("@lune/process")
local fs = require("@lune/fs")
local Logger = require("../lib/Logger")
local Config = require("../lib/Config")

local Shell = {}
Shell.__index = Shell

export type ShellInstance = typeof(setmetatable({} :: {
    _cwd: string,
    _env: {[string]: string},
    _os: string,
    _shell: string,
}, Shell))

local _instance: ShellInstance? = nil
local _agentShells: {[string]: ShellInstance} = {}

function Shell.get(): ShellInstance
    if not _instance then
        _instance = Shell.new()
    end
    return _instance :: ShellInstance
end

-- Get or create an isolated shell for a specific agent.
-- Each agent gets its own CWD and env state to avoid conflicts.
function Shell.forAgent(agentId: string): ShellInstance
    if not _agentShells[agentId] then
        _agentShells[agentId] = Shell.new()
    end
    return _agentShells[agentId]
end

-- Clean up an agent's shell when it finishes.
function Shell.releaseAgent(agentId: string)
    _agentShells[agentId] = nil
end

function Shell.new(): ShellInstance
    local self = setmetatable({}, Shell)
    self._os = process.os
    self._cwd = process.cwd
    self._env = {}
    
    -- Sync initial CWD
    pcall(function() self._cwd = process.cwd end)
    
     -- Determine shell
    local shellPref = Config.shell_preference
    if self._os == "windows" then
        if shellPref == "cmd" then self._shell = "cmd"
        elseif shellPref == "powershell" then self._shell = "powershell"
        else self._shell = "pwsh" end
    else
        self._shell = "bash"
    end
    
    return self
end

function Shell:execute(command: string, timeout: number?): string
    -- 1. Check for State Changes (CD / ENV)
    -- This is a naive parser but covers 90% of agent usage
    
    local cmdTrim = command:match("^%s*(.-)%s*$") or ""
    
    -- Handle CD: We don't pre-resolve the path here.
    -- Instead, the CWD marker appended to every command (see below) will
    -- capture the real working directory after execution, so cd commands
    -- are tracked automatically via the __COPAL_CWD__ output parsing.
    
    -- 2. Construct Chain
    local chain = ""
    
    -- Prepend CWD
    if self._os == "windows" then
        chain = "cd /d " .. self:quote(self._cwd)
    else
        chain = "cd " .. self:quote(self._cwd)
    end
    
    -- Prepend Env Vars
    for k, v in pairs(self._env) do
        if self._os == "windows" then
             -- Powershell env vars are different
             if self._shell == "cmd" then
                 chain = chain .. " && set " .. k .. "=" .. v
             else
                 chain = chain .. "; $env:" .. k .. "='" .. v .. "'"
             end
        else
            chain = chain .. " && export " .. k .. "=" .. self:quote(v)
        end
    end
    
    -- Append User Command
    if self._os == "windows" and self._shell ~= "cmd" then
        chain = chain .. "; " .. command
    else
        chain = chain .. " && " .. command
    end
    
    -- capture PWD after command to sync state?
    -- Example: command was "cd ..", we need to know new PWD.
    -- Append "current directory" output
    if self._os == "windows" then
         if self._shell == "cmd" then
             chain = chain .. " && echo __COPAL_CWD__ && cd"
         else
             chain = chain .. "; Write-Output '__COPAL_CWD__'; Get-Location"
         end
    else
        chain = chain .. " && echo __COPAL_CWD__ && pwd"
    end
    
    -- 3. Execute
    Logger.debug("Shell Exec: " .. chain)
    
    local prog, params
    if self._os == "windows" then
        if self._shell == "cmd" then
            prog = "cmd"
            params = {"/c", chain}
        else
            prog = self._shell
            params = {"-Command", chain}
        end
    else
        prog = "bash"
        params = {"-c", chain}
    end
    
    local result = process.create(prog, params)
    
    -- Read stdout
    local output = ""
    local chunk = result.stdout:read()
    while chunk do
        output = output .. chunk
        chunk = result.stdout:read()
    end

    -- Read stderr
    local stderr = ""
    local errChunk = result.stderr:read()
    while errChunk do
        stderr = stderr .. errChunk
        errChunk = result.stderr:read()
    end

    if #stderr > 0 then
        output = output .. "\nSTDERR: " .. stderr
    end
    
    -- 4. Parse New CWD
    local split = output:split("__COPAL_CWD__")
    if #split > 1 then
        local realOutput = split[1]
        local debugInfo = split[2]
        
        -- Clean up debugInfo to get path
        local newCwd = debugInfo:match("^%s*(.-)%s*$")
        if newCwd and #newCwd > 0 then
            -- Handle Powershell Get-Location object output:
            -- "Path \n ---- \n C:\Users\..."
            if newCwd:find("Path") and newCwd:find("%-%-%-%-") then
                local path = newCwd:match("%-%-%-%-+%s*(.+)")
                if path then
                    newCwd = path:match("^%s*(.-)%s*$") or newCwd
                end
            end

            -- Only update if it looks like a valid path
            if #newCwd > 0 then
                self._cwd = newCwd
            end
        end
        
        return realOutput:match("^%s*(.-)%s*$") or ""
    else
        -- If we didn't get CWD marker, command failed before that.
        return output
    end
end

function Shell:quote(str: string): string
    return '"' .. str .. '"'
end

function Shell:stop() end
function Shell:restart() end

return Shell
