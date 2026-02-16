--!strict

local Bookmark = {}

-- In-memory bookmark storage (persists for the session)
local bookmarks: { [string]: { path: string, line: number?, note: string? } } = {}

Bookmark.bookmarkTool = {
    name = "bookmark",
    description = "Save a bookmark to a file location for quick reference later. Useful for marking important code locations you'll need to revisit. Bookmarks persist for the current session.",
    parameters = {
        type = "object",
        properties = {
            name = { type = "string", description = "Bookmark name (e.g. 'auth-handler', 'bug-location')" },
            path = { type = "string", description = "File path to bookmark" },
            line = { type = "number", description = "Optional line number" },
            note = { type = "string", description = "Optional note about this location" },
        },
        required = { "name", "path" },
    },
    execute = function(args)
        if not args.name or not args.path then
            return "Error: name and path required"
        end

        bookmarks[args.name] = {
            path = args.path,
            line = args.line,
            note = args.note,
        }

        local display = args.path
        if args.line then display ..= ":" .. args.line end
        if args.note then display ..= " — " .. args.note end

        return "Bookmarked '" .. args.name .. "' → " .. display
    end,
}

Bookmark.listBookmarksTool = {
    name = "list_bookmarks",
    description = "List all saved bookmarks for the current session.",
    parameters = {
        type = "object",
        properties = {},
        required = {},
    },
    execute = function(_args)
        local count = 0
        local lines: { string } = {}

        for name, bm in pairs(bookmarks) do
            count += 1
            local display = bm.path
            if bm.line then display ..= ":" .. bm.line end
            if bm.note then display ..= " — " .. bm.note end
            table.insert(lines, "  " .. name .. " → " .. display)
        end

        if count == 0 then
            return "No bookmarks saved. Use 'bookmark' to save one."
        end

        table.sort(lines)
        return count .. " bookmark(s):\n" .. table.concat(lines, "\n")
    end,
}

Bookmark.removeBookmarkTool = {
    name = "remove_bookmark",
    description = "Remove a saved bookmark by name.",
    parameters = {
        type = "object",
        properties = {
            name = { type = "string", description = "Bookmark name to remove" },
        },
        required = { "name" },
    },
    execute = function(args)
        if not args.name then return "Error: name required" end
        if not bookmarks[args.name] then
            return "Bookmark '" .. args.name .. "' not found."
        end
        bookmarks[args.name] = nil
        return "Removed bookmark '" .. args.name .. "'."
    end,
}

return Bookmark
