--!strict
local stdio = require("@lune/stdio")
local process = require("@lune/process")

local Logger = {}

local COLORS = {
    RESET = "\27[0m",
    RED = "\27[31m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    BLUE = "\27[34m",
    CYAN = "\27[36m",
    WHITE = "\27[37m",
    GRAY = "\27[90m",
}

function Logger.info(msg: string)
    stdio.write(COLORS.BLUE .. "[INFO] " .. COLORS.RESET .. msg .. "\n")
end

function Logger.success(msg: string)
    stdio.write(COLORS.GREEN .. "[SUCCESS] " .. COLORS.RESET .. msg .. "\n")
end

function Logger.warn(msg: string)
    stdio.write(COLORS.YELLOW .. "[WARN] " .. COLORS.RESET .. msg .. "\n")
end

function Logger.error(msg: string)
    stdio.write(COLORS.RED .. "[ERROR] " .. COLORS.RESET .. msg .. "\n")
end

function Logger.debug(msg: string)
    if process.env.DEBUG then
        stdio.write(COLORS.GRAY .. "[DEBUG] " .. COLORS.RESET .. msg .. "\n")
    end
end

return Logger
