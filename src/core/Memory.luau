--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local LLMClient = require("../models/LLMClient")
local Logger = require("../lib/Logger")
local Config = require("../lib/Config")

local Memory = {}
Memory.__index = Memory

type Vector = {number}
export type MemoryItem = {
    content: string,
    vector: Vector,
    timestamp: number,
    tags: {string}?,
    metadata: {[string]: any}?
}

local MEMORY_FILE = ".copal/memory.json"

local _instance = nil

function Memory.get()
    if not _instance then _instance = Memory.new() end
    return _instance
end

function Memory.new()
    local self = setmetatable({}, Memory)
    self.items = {} :: {MemoryItem}
    self:load()
    return self
end

function Memory:load()
    if fs.isFile(MEMORY_FILE) then
        local success, data = pcall(function() 
            return serde.decode("json", fs.readFile(MEMORY_FILE)) 
        end)
        if success and type(data) == "table" then
            self.items = data
        end
    end
end

function Memory:save()
    -- Ensure directory exists
    if not fs.isDir(".copal") then
        pcall(function() fs.writeDir(".copal") end)
    end
    
    local content = serde.encode("json", self.items)
    fs.writeFile(MEMORY_FILE, content)
end

function Memory:add(content: string, tags: {string}?, metadata: {[string]: any}?)
    local provider = Config.getActive()
    if not provider.models.embedding or #provider.models.embedding == 0 then
        Logger.error("No embedding model configured. Set one in Settings > Model Selection or add 'embedding' to your provider config.")
        return false
    end

    local vector = LLMClient.embedding(content)
    if not vector then
        Logger.error("Failed to generate embedding for memory (model: " .. provider.models.embedding .. ")")
        return false
    end
    
    local item: MemoryItem = {
        content = content,
        vector = vector,
        timestamp = os.time(),
        tags = tags or {},
        metadata = metadata or {}
    }
    
    table.insert(self.items, item)

    -- Prune oldest memories if over capacity
    local maxItems = Config.memory_max_items or 500
    if #self.items > maxItems then
        local pruned = #self.items - maxItems
        local kept = {}
        for i = pruned + 1, #self.items do
            table.insert(kept, self.items[i])
        end
        self.items = kept
        Logger.info("Pruned " .. pruned .. " oldest memories (limit: " .. maxItems .. ")")
    end

    self:save()
    Logger.info("Saved memory: " .. content:sub(1, 40) .. "...")
    return true
end

-- Cosine Similarity
local function cosineSimilarity(v1: Vector, v2: Vector): number
    local dot = 0
    local mag1 = 0
    local mag2 = 0
    
    if #v1 ~= #v2 then return 0 end
    
    for i = 1, #v1 do
        dot += v1[i] * v2[i]
        mag1 += v1[i] * v1[i]
        mag2 += v2[i] * v2[i]
    end
    
    if mag1 == 0 or mag2 == 0 then return 0 end
    
    return dot / (math.sqrt(mag1) * math.sqrt(mag2))
end

function Memory:search(query: string, limit: number?): { {item: MemoryItem, score: number} }
    limit = limit or 3
    local queryVector = LLMClient.embedding(query)
    if not queryVector then
        Logger.warn("Memory search failed: could not generate embedding for query.")
        return {}
    end
    
    local results = {}
    
    for _, item in ipairs(self.items) do
        local score = cosineSimilarity(queryVector, item.vector)
        table.insert(results, {item = item, score = score})
    end
    
    -- Sort descending
    table.sort(results, function(a, b) return a.score > b.score end)
    
    -- Slice
    local topK = {}
    for i = 1, math.min(limit, #results) do
        local threshold = Config.memory_relevance_threshold or 0.4
        if results[i].score > threshold then
            table.insert(topK, results[i])
        end
    end
    
    return topK
end

return Memory
