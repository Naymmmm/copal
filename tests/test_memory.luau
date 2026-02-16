local Memory = require("../src/core/Memory")
local Config = require("../src/lib/Config")
local Auth = require("../src/core/Auth")

print("--- Testing Vector Memory ---")
Config.load()
Auth.login()

local provider = Config.getActive()
if not provider.models.embedding then
    print("WARNING: No embedding model configured. Test will likely fail.")
else
    print("Embedding Model: " .. provider.models.embedding)
end

local mem = Memory.get()

-- Add memories
print("\nSaving memories...")
mem:add("The API key for the weather service is 12345-ABCDE.")
mem:add("The user prefers using Luau over Python.")
mem:add("The project architecture is modular with a central Swarm.")

-- Search
print("\nSearching: 'What is the user's favorite language?'")
local results = mem:search("What is the user's favorite language?", 1)
if #results > 0 then
    print("Match: " .. results[1].item.content)
    print("Score: " .. results[1].score)
else
    print("No match found.")
end

print("\nSearching: 'weather api'")
local results2 = mem:search("weather api", 1)
if #results2 > 0 then
    print("Match: " .. results2[1].item.content)
    print("Score: " .. results2[1].score)
else
    print("No match found.")
end
