local process = require("@lune/process")
local stdio = require("@lune/stdio")

local env = process.env
print("HOME:", env.HOME)
print("USERPROFILE:", env.USERPROFILE)
print("OS:", process.os)
