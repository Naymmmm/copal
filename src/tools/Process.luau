--!strict
local process = require("@lune/process")
local Task = require("@lune/task")
local net = require("@lune/net")

local Process = {}

-- Track background processes
local backgroundProcesses: { [string]: { command: string, startTime: number, output: string?, done: boolean } } = {}
local nextId = 1

Process.spawnBackgroundTool = {
    name = "spawn_background",
    description = "Start a command in the background (e.g. dev server, watcher). Returns an ID to check status or kill it later. Output is captured and available via check_background.",
    parameters = {
        type = "object",
        properties = {
            command = { type = "string", description = "Command to run (e.g. 'npm run dev', 'python -m http.server 8080')" },
            label = { type = "string", description = "Optional label for this process" },
        },
        required = { "command" },
    },
    execute = function(args)
        if not args.command then return "Error: command required" end

        local id = tostring(nextId)
        nextId += 1

        local label = args.label or args.command:sub(1, 40)
        backgroundProcesses[id] = {
            command = args.command,
            startTime = os.clock(),
            output = nil,
            done = false,
        }

        -- Spawn in background
        Task.spawn(function()
            local Shell = require("../core/Shell")
            local output = Shell.get():execute(args.command)
            if backgroundProcesses[id] then
                backgroundProcesses[id].output = output
                backgroundProcesses[id].done = true
            end
        end)

        return "Started background process #" .. id .. " (" .. label .. ")\nUse check_background with id='" .. id .. "' to see output, or kill_process to stop it."
    end,
}

Process.checkBackgroundTool = {
    name = "check_background",
    description = "Check the status and output of a background process started with spawn_background.",
    parameters = {
        type = "object",
        properties = {
            id = { type = "string", description = "Process ID from spawn_background" },
        },
        required = { "id" },
    },
    execute = function(args)
        if not args.id then return "Error: id required" end

        local proc = backgroundProcesses[args.id]
        if not proc then
            -- List all processes
            local lines = { "Process #" .. args.id .. " not found. Active processes:" }
            for pid, p in pairs(backgroundProcesses) do
                local status = if p.done then "done" else "running"
                table.insert(lines, "  #" .. pid .. " [" .. status .. "] " .. p.command)
            end
            return table.concat(lines, "\n")
        end

        local status = if proc.done then "DONE" else "RUNNING"
        local elapsed = math.floor(os.clock() - proc.startTime)
        local output = proc.output or "(no output yet)"

        if #output > 8000 then
            output = output:sub(-8000) .. "\n... (showing last 8000 chars)"
        end

        return "Process #" .. args.id .. " [" .. status .. "] (" .. elapsed .. "s)\nCommand: " .. proc.command .. "\n\n" .. output
    end,
}

Process.checkPortTool = {
    name = "check_port",
    description = "Check if a port is open/listening on localhost. Useful for verifying dev servers are running.",
    parameters = {
        type = "object",
        properties = {
            port = { type = "number", description = "Port number to check" },
            host = { type = "string", description = "Host to check (default: 127.0.0.1)" },
        },
        required = { "port" },
    },
    execute = function(args)
        if not args.port then return "Error: port required" end

        local host = args.host or "127.0.0.1"
        local port = math.floor(args.port)

        -- Try connecting via HTTP
        local url = "http://" .. host .. ":" .. port .. "/"
        local ok, _ = pcall(function()
            return net.request({
                url = url,
                method = "GET",
            })
        end)

        if ok then
            return "Port " .. port .. " on " .. host .. " is OPEN (accepting connections)."
        end

        -- If HTTP fails, try a raw connection test via platform tools
        local checkOk, result = pcall(function()
            return process.spawn("bash", {
                "-c",
                "(echo >/dev/tcp/" .. host .. "/" .. port .. ") 2>/dev/null && echo OPEN || echo CLOSED"
            })
        end)

        if checkOk and result.ok then
            if result.stdout:find("OPEN") then
                return "Port " .. port .. " on " .. host .. " is OPEN."
            else
                return "Port " .. port .. " on " .. host .. " is CLOSED (not listening)."
            end
        end

        return "Port " .. port .. " on " .. host .. " appears CLOSED (connection refused)."
    end,
}

Process.killProcessTool = {
    name = "kill_process",
    description = "Kill a process by PID or by port. Use this to stop dev servers or runaway processes.",
    parameters = {
        type = "object",
        properties = {
            pid = { type = "number", description = "Process ID to kill" },
            port = { type = "number", description = "Kill process listening on this port" },
            background_id = { type = "string", description = "Kill a background process by its spawn_background ID" },
        },
        required = {},
    },
    execute = function(args)
        -- Kill by background ID (mark as done)
        if args.background_id then
            local proc = backgroundProcesses[args.background_id]
            if proc then
                proc.done = true
                proc.output = (proc.output or "") .. "\n[Killed by user]"
                return "Background process #" .. args.background_id .. " marked as killed."
            end
            return "Background process #" .. args.background_id .. " not found."
        end

        -- Kill by PID
        if args.pid then
            local pid = math.floor(args.pid)
            -- Try POSIX kill first
            local ok, result = pcall(function()
                return process.spawn("kill", { tostring(pid) })
            end)
            if ok and result.ok then
                return "Sent SIGTERM to PID " .. pid
            end

            -- Try Windows taskkill
            ok, result = pcall(function()
                return process.spawn("taskkill", { "/PID", tostring(pid), "/F" })
            end)
            if ok and result.ok then
                return "Killed PID " .. pid
            end

            return "Error: could not kill PID " .. pid .. ". Process may not exist."
        end

        -- Kill by port
        if args.port then
            local port = math.floor(args.port)

            -- Try lsof (macOS/Linux)
            local ok, result = pcall(function()
                return process.spawn("lsof", { "-ti", ":" .. port })
            end)
            if ok and result.ok and #result.stdout > 0 then
                local pids = result.stdout:gsub("%s+$", "")
                for pidStr in pids:gmatch("%S+") do
                    pcall(function() process.spawn("kill", { pidStr }) end)
                end
                return "Killed process(es) on port " .. port .. ": PID " .. pids
            end

            -- Try netstat + taskkill (Windows)
            ok, result = pcall(function()
                return process.spawn("cmd", { "/C", "for /f \"tokens=5\" %a in ('netstat -ano ^| findstr :" .. port .. " ^| findstr LISTENING') do taskkill /PID %a /F" })
            end)
            if ok then
                return "Attempted to kill process on port " .. port
            end

            return "Error: could not find/kill process on port " .. port
        end

        return "Error: provide pid, port, or background_id"
    end,
}

return Process
