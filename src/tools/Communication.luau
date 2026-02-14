--!strict
local Monitor = require("../lib/Monitor")

local Communication = {}

-- ═══════════════════════════════════════
--  Broadcast: Send message to ALL agents
-- ═══════════════════════════════════════

Communication.broadcastTool = {
    name = "broadcast",
    description = "Broadcast a message to ALL other agents in the swarm. Use this to share important findings, results, or warnings that everyone should know about. Every agent will see this message on their next iteration.",
    parameters = {
        type = "object",
        properties = {
            message = {type = "string", description = "The message to broadcast to all agents"},
            priority = {
                type = "string",
                description = "Priority level: 'info' (general update), 'important' (key finding), 'urgent' (blocking issue). Default: 'info'",
                enum = {"info", "important", "urgent"}
            }
        },
        required = {"message"}
    },
    execute = function(args)
        if not args.message then return "Error: message required" end
        local priority = args.priority or "info"
        Monitor.emit("log", "Broadcast", "[" .. priority:upper() .. "] " .. args.message)
        return "Message broadcasted to all agents with priority: " .. priority
    end
}

-- ═══════════════════════════════════════
--  Whisper: Send message to ONE agent
-- ═══════════════════════════════════════

Communication.whisperTool = {
    name = "whisper",
    description = "Send a private message to a specific agent by their ID (e.g. 'Agent 1', 'Agent 3'). Use this instead of broadcast when the information is only relevant to one agent, like sharing a result they requested or coordinating on a shared file.",
    parameters = {
        type = "object",
        properties = {
            target = {type = "string", description = "The target agent ID, e.g. 'Agent 2'"},
            message = {type = "string", description = "The private message to send"}
        },
        required = {"target", "message"}
    },
    execute = function(args)
        if not args.target then return "Error: target agent ID required" end
        if not args.message then return "Error: message required" end
        Monitor.emit("log", "Whisper", "→ " .. args.target .. ": " .. args.message)
        return "Message sent to " .. args.target
    end
}

-- ═══════════════════════════════════════
--  Request Help: Ask for collaboration
-- ═══════════════════════════════════════

Communication.requestHelpTool = {
    name = "request_help",
    description = "Request help from other agents when you are stuck or need specialized expertise. Describe what you need and what you've already tried. Other agents will see this and can respond via broadcast or whisper.",
    parameters = {
        type = "object",
        properties = {
            topic = {type = "string", description = "Brief description of what you need help with"},
            details = {type = "string", description = "What you've tried so far and why you're stuck"},
            expertise_needed = {type = "string", description = "What kind of expertise would be helpful (e.g., 'file system', 'API', 'debugging')"}
        },
        required = {"topic", "details"}
    },
    execute = function(args)
        if not args.topic then return "Error: topic required" end
        if not args.details then return "Error: details required" end
        local expertise = args.expertise_needed or "any"
        Monitor.emit("log", "Help Request", "HELP NEEDED [" .. expertise .. "]: " .. args.topic .. " - " .. args.details)
        return "Help request posted. Other agents will see this on their next iteration."
    end
}

-- ═══════════════════════════════════════
--  Report Progress: Share task status
-- ═══════════════════════════════════════

Communication.reportProgressTool = {
    name = "report_progress",
    description = "Report your current task progress to the swarm. Useful for keeping the team aware of what's done, what's in progress, and what's remaining.",
    parameters = {
        type = "object",
        properties = {
            status = {
                type = "string",
                description = "Your current status: 'in_progress', 'blocked', 'completed', 'failed'",
                enum = {"in_progress", "blocked", "completed", "failed"}
            },
            summary = {type = "string", description = "Brief summary of what you've accomplished or where you're stuck"},
            files_modified = {type = "string", description = "Comma-separated list of files you've created or modified (helps avoid conflicts)"}
        },
        required = {"status", "summary"}
    },
    execute = function(args)
        if not args.status then return "Error: status required" end
        if not args.summary then return "Error: summary required" end
        local files = args.files_modified or "none"
        Monitor.emit("log", "Progress", "[" .. args.status:upper() .. "] " .. args.summary .. " | Files: " .. files)
        return "Progress reported: " .. args.status
    end
}

return Communication
