--!strict
local Task = require("@lune/task")
local stdio = require("@lune/stdio")

local Monitor = {}
local listeners = {}

export type EventType = "log" | "thought" | "tool_call" | "tool_result" | "agent_state" | "completion"
export type Event = {
    type: EventType,
    source: string, -- e.g., "Agent 1", "Director", "CEO"
    data: any,
    timestamp: number
}

function Monitor.emit(eventType: EventType, source: string, data: any)
    local event: Event = {
        type = eventType,
        source = source,
        data = data,
        timestamp = os.time()
    }
    
    -- Dispatch to listeners
    for _, callback in ipairs(listeners) do
        Task.spawn(function()
            callback(event)
        end)
    end
end

function Monitor.subscribe(callback: (Event) -> ())
    table.insert(listeners, callback)
end

function Monitor.log(source: string, message: string)
    Monitor.emit("log", source, message)
end

function Monitor.thought(source: string, thought: string)
    Monitor.emit("thought", source, thought)
end

function Monitor.completion(source: string, text: string)
    Monitor.emit("completion", source, text)
end

return Monitor
