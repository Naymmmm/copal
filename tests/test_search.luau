local process = require("@lune/process")
local Search = require("../src/tools/Search")
local Config = require("../src/lib/Config")
local Auth = require("../src/core/Auth")

local function test()
    print("Testing Search Tool...")
    Config.load()
    Auth.login() -- Load keys
    
    local provider = Config.getActive()
    print("Active Provider:", Config.active_provider)
    print("Search Model:", provider.models.search)
    
    local query = "What is the current version of Lune runtime?"
    print("Querying:", query)
    
    local result = Search.searchTool.execute({query = query})
    print("\nResult:")
    print(result)
end

test()
