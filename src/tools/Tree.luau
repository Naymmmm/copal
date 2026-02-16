--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Config = require("../lib/Config")

local Tree = {}

local SKIP_DIRS: { [string]: boolean } = {
    [".git"] = true,
    ["node_modules"] = true,
    [".next"] = true,
    ["target"] = true,
    ["__pycache__"] = true,
    [".venv"] = true,
    ["dist"] = true,
    ["build"] = true,
    [".cache"] = true,
}

local function isSafePath(path: string): (boolean, string?)
    if Config.security_level == "full_access" then
        return true
    end
    if path:find("%.%.") then
        return false, "Path contains '..' which is blocked in Restricted Mode."
    end
    if path:match("^/") or path:match("^%a:") then
        local cwd = process.cwd
        local normPath = path:gsub("\\", "/")
        local normCwd = cwd:gsub("\\", "/")
        if not normPath:find(normCwd, 1, true) then
            return false, "Path is outside CWD in Restricted Mode."
        end
    end
    return true
end

Tree.treeTool = {
    name = "tree",
    description = "Show directory structure as an indented tree. Skips .git, node_modules, and other heavy directories. Great for understanding project layout quickly.",
    parameters = {
        type = "object",
        properties = {
            path = { type = "string", description = "Root directory (default: '.')" },
            max_depth = { type = "number", description = "Maximum depth to display (default: 4)" },
            show_files = { type = "boolean", description = "Show files, not just directories (default: true)" },
            max_items = { type = "number", description = "Maximum total items to display (default: 200)" },
        },
        required = {},
    },
    execute = function(args)
        local rootPath = args.path or "."
        local maxDepth = args.max_depth or 4
        local showFiles = if args.show_files == nil then true else args.show_files
        local maxItems = args.max_items or 200

        local safe, reason = isSafePath(rootPath)
        if not safe then return "Security Error: " .. tostring(reason) end

        local lines: { string } = {}
        local itemCount = 0

        local function walk(dir: string, prefix: string, depth: number)
            if depth > maxDepth or itemCount >= maxItems then return end

            local ok, entries = pcall(function() return fs.readDir(dir) end)
            if not ok then return end

            -- Sort entries: directories first, then files
            local dirs: { string } = {}
            local files: { string } = {}

            for _, entry in ipairs(entries) do
                if SKIP_DIRS[entry] then continue end
                local fullPath = if dir == "." then entry else dir .. "/" .. entry
                local isDir = pcall(function() return fs.isDir(fullPath) end) and fs.isDir(fullPath)
                if isDir then
                    table.insert(dirs, entry)
                else
                    table.insert(files, entry)
                end
            end

            table.sort(dirs)
            table.sort(files)

            -- Combine: dirs first, then files
            local all: { { name: string, isDir: boolean } } = {}
            for _, d in ipairs(dirs) do
                table.insert(all, { name = d, isDir = true })
            end
            if showFiles then
                for _, f in ipairs(files) do
                    table.insert(all, { name = f, isDir = false })
                end
            end

            for i, item in ipairs(all) do
                if itemCount >= maxItems then
                    table.insert(lines, prefix .. "... (truncated)")
                    return
                end

                local isLast = (i == #all)
                local connector = if isLast then "└── " else "├── "
                local childPrefix = if isLast then "    " else "│   "

                local display = item.name
                if item.isDir then
                    display ..= "/"
                end

                table.insert(lines, prefix .. connector .. display)
                itemCount += 1

                if item.isDir then
                    local fullPath = if dir == "." then item.name else dir .. "/" .. item.name
                    walk(fullPath, prefix .. childPrefix, depth + 1)
                end
            end
        end

        table.insert(lines, rootPath .. "/")
        walk(rootPath, "", 1)

        if itemCount >= maxItems then
            table.insert(lines, "\n... (truncated at " .. maxItems .. " items, use max_depth or path to narrow)")
        end

        return table.concat(lines, "\n")
    end,
}

return Tree
