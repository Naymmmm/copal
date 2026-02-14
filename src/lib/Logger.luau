--!strict
local stdio = require("@lune/stdio")
local process = require("@lune/process")

local Logger = {}

-- Nerd Font icons
local NF = {
    INFO    = " ",  -- nf-fa-info_circle
    SUCCESS = " ",  -- nf-fa-check_circle
    WARN    = " ",  -- nf-fa-exclamation_triangle
    ERROR   = " ",  -- nf-fa-times_circle
    DEBUG   = " ",  -- nf-fa-bug
}

local COLORS = {
    RESET  = "\27[0m",
    RED    = "\27[31m",
    GREEN  = "\27[32m",
    YELLOW = "\27[33m",
    BLUE   = "\27[34m",
    CYAN   = "\27[36m",
    WHITE  = "\27[37m",
    GRAY   = "\27[90m",
}

function Logger.info(msg: string)
    stdio.write(COLORS.BLUE .. NF.INFO .. "INFO " .. COLORS.RESET .. msg .. "\n")
end

function Logger.success(msg: string)
    stdio.write(COLORS.GREEN .. NF.SUCCESS .. "OK " .. COLORS.RESET .. msg .. "\n")
end

function Logger.warn(msg: string)
    stdio.write(COLORS.YELLOW .. NF.WARN .. "WARN " .. COLORS.RESET .. msg .. "\n")
end

function Logger.error(msg: string)
    stdio.write(COLORS.RED .. NF.ERROR .. "ERR " .. COLORS.RESET .. msg .. "\n")
end

function Logger.debug(msg: string)
    if process.env.DEBUG then
        stdio.write(COLORS.GRAY .. NF.DEBUG .. "DBG " .. COLORS.RESET .. msg .. "\n")
    end
end

return Logger
