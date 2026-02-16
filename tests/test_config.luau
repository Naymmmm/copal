--!strict
local stdio = require("@lune/stdio")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local function testConfig()
    stdio.write(stdio.style("bold") .. "Testing Config...\n" .. stdio.style("reset"))

    -- We test Config.load() by writing a temporary config file and verifying merge behavior.
    -- Save original config path, use a temp one.
    local Config = require("../src/lib/Config")
    local originalFile = Config.configFile
    local testFile = "test_copal_config.json"
    Config.configFile = testFile

    -- 1. Test that defaults exist
    local provider = Config.providers.opencode
    if provider and provider.models.low and provider.models.embedding then
        stdio.write("[PASS] Default provider has all model fields\n")
    else
        stdio.write("[FAIL] Default provider missing fields\n")
    end

    -- 2. Test partial merge preserves defaults
    -- Write a config that only overrides 'low' model
    local partialConfig = {
        active_provider = "opencode",
        providers = {
            opencode = {
                key = "test-key-123",
                models = {
                    low = "custom-model-low"
                }
            }
        }
    }
    fs.writeFile(testFile, serde.encode("json", partialConfig))
    Config.load()

    local merged = Config.providers.opencode
    if merged.models.low == "custom-model-low" then
        stdio.write("[PASS] Partial merge overrides specified field\n")
    else
        stdio.write("[FAIL] Low model not overridden: " .. merged.models.low .. "\n")
    end

    if merged.models.medium == "gpt-4o" then
        stdio.write("[PASS] Partial merge preserves unspecified defaults (medium)\n")
    else
        stdio.write("[FAIL] Medium model changed: " .. merged.models.medium .. "\n")
    end

    if merged.models.embedding == "text-embedding-3-small" then
        stdio.write("[PASS] Partial merge preserves embedding default\n")
    else
        stdio.write("[FAIL] Embedding model changed: " .. tostring(merged.models.embedding) .. "\n")
    end

    if merged.key == "test-key-123" then
        stdio.write("[PASS] Key loaded from config\n")
    else
        stdio.write("[FAIL] Key mismatch: " .. tostring(merged.key) .. "\n")
    end

    -- 3. Test mcpServers load
    local mcpConfig = {
        active_provider = "opencode",
        mcpServers = {
            testserver = { command = "npx", args = {"-y", "test-server"} }
        }
    }
    fs.writeFile(testFile, serde.encode("json", mcpConfig))
    Config.load()

    if Config.mcpServers and Config.mcpServers.testserver then
        local srv = Config.mcpServers.testserver
        if srv.command == "npx" and #srv.args == 2 then
            stdio.write("[PASS] MCP server config loaded\n")
        else
            stdio.write("[FAIL] MCP server config malformed\n")
        end
    else
        stdio.write("[FAIL] MCP servers not loaded\n")
    end

    -- 4. Test save/load round-trip
    Config.active_provider = "openai"
    Config.security_level = "full_access"
    Config.rate_limit_delay = 0.5
    Config.save()

    -- Reset and reload
    Config.active_provider = "opencode"
    Config.security_level = "restricted"
    Config.rate_limit_delay = 0
    Config.load()

    if Config.active_provider == "openai" then
        stdio.write("[PASS] Save/load round-trip: active_provider\n")
    else
        stdio.write("[FAIL] Round-trip active_provider: " .. Config.active_provider .. "\n")
    end

    if Config.security_level == "full_access" then
        stdio.write("[PASS] Save/load round-trip: security_level\n")
    else
        stdio.write("[FAIL] Round-trip security_level: " .. Config.security_level .. "\n")
    end

    if Config.rate_limit_delay == 0.5 then
        stdio.write("[PASS] Save/load round-trip: rate_limit_delay\n")
    else
        stdio.write("[FAIL] Round-trip rate_limit_delay: " .. tostring(Config.rate_limit_delay) .. "\n")
    end

    -- Cleanup
    if fs.isFile(testFile) then fs.removeFile(testFile) end
    Config.configFile = originalFile
    Config.load() -- restore real config
end

testConfig()
