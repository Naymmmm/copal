--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local Config = require("../lib/Config")

local Glob = {}

-- ═══════════════════════════════════════
--  Security: Path Safety Check
-- ═══════════════════════════════════════

local function isSafePath(path: string): (boolean, string?)
	if Config.security_level == "full_access" then
		return true
	end

	if path:find("%.%.") then
		return false, "Path contains '..' (Parent Directory Traversal) which is blocked in Restricted Mode."
	end

	if path:match("^/") or path:match("^%a:") then
		local cwd = process.cwd
		local normPath = path:gsub("\\", "/")
		local normCwd = cwd:gsub("\\", "/")

		if not normPath:find(normCwd, 1, true) then
			return false, "Path is outside Current Working Directory (" .. cwd .. ") in Restricted Mode."
		end
	end

	return true
end

-- ═══════════════════════════════════════
--  Glob Pattern Matching
-- ═══════════════════════════════════════

-- Directories to always skip
local SKIP_DIRS: {[string]: boolean} = {
	[".git"] = true,
	["node_modules"] = true,
	[".next"] = true,
	["target"] = true,
	["__pycache__"] = true,
	[".venv"] = true,
}

local MAX_DEPTH = 20

-- Match a single segment against a pattern segment
-- Supports * (any chars) and ? (single char)
local function matchSegment(pattern: string, segment: string): boolean
	-- Convert glob pattern to Lua pattern
	local luaPattern = "^"
	local i = 1
	while i <= #pattern do
		local c = pattern:sub(i, i)
		if c == "*" then
			luaPattern ..= ".*"
		elseif c == "?" then
			luaPattern ..= "."
		elseif c:find("[%(%)%.%%%+%-%^%$%[]") then
			luaPattern ..= "%" .. c
		else
			luaPattern ..= c
		end
		i += 1
	end
	luaPattern ..= "$"

	return segment:match(luaPattern) ~= nil
end

-- Match a full path against a glob pattern
-- Supports ** for recursive directory matching
local function matchGlob(pattern: string, path: string): boolean
	-- Normalize separators
	local normPattern = pattern:gsub("\\", "/")
	local normPath = path:gsub("\\", "/")

	-- Split into segments
	local patternSegs: {string} = {}
	for seg in normPattern:gmatch("[^/]+") do
		table.insert(patternSegs, seg)
	end

	local pathSegs: {string} = {}
	for seg in normPath:gmatch("[^/]+") do
		table.insert(pathSegs, seg)
	end

	-- Recursive matching with ** support
	local function match(pi: number, si: number): boolean
		-- Both exhausted = match
		if pi > #patternSegs and si > #pathSegs then
			return true
		end

		-- Pattern exhausted but path remains = no match
		if pi > #patternSegs then
			return false
		end

		local pSeg = patternSegs[pi]

		-- ** matches zero or more directory segments
		if pSeg == "**" then
			-- Try matching zero segments (skip **)
			if match(pi + 1, si) then
				return true
			end
			-- Try matching one or more segments
			if si <= #pathSegs then
				return match(pi, si + 1)
			end
			return false
		end

		-- Path exhausted but pattern remains = no match
		if si > #pathSegs then
			return false
		end

		-- Normal segment match
		if matchSegment(pSeg, pathSegs[si]) then
			return match(pi + 1, si + 1)
		end

		return false
	end

	return match(1, 1)
end

-- ═══════════════════════════════════════
--  Directory Walker
-- ═══════════════════════════════════════

local function walkDir(basePath: string, pattern: string, maxResults: number): {string}
	local results: {string} = {}

	local function walk(dir: string, depth: number)
		if depth > MAX_DEPTH or #results >= maxResults then
			return
		end

		local ok, entries = pcall(function()
			return fs.readDir(dir)
		end)
		if not ok then
			return
		end

		for _, entry in ipairs(entries) do
			if #results >= maxResults then
				return
			end

			-- Skip known heavy directories
			if SKIP_DIRS[entry] then
				continue
			end

			local fullPath = if dir == "." then entry else dir .. "/" .. entry

			local isDir = pcall(function()
				return fs.isDir(fullPath)
			end) and fs.isDir(fullPath)

			if isDir then
				-- Check if directory itself matches pattern (unlikely but possible)
				walk(fullPath, depth + 1)
			else
				-- Normalize path for matching
				local matchPath = fullPath:gsub("\\", "/")
				if matchGlob(pattern, matchPath) then
					table.insert(results, matchPath)
				end
			end
		end
	end

	walk(basePath, 0)
	return results
end

-- ═══════════════════════════════════════
--  Glob Tool
-- ═══════════════════════════════════════

Glob.globTool = {
	name = "glob",
	description = "Find files matching a glob pattern. Supports ** (recursive), * (wildcard), ? (single char). Skips .git, node_modules, and other heavy directories. Use this to discover files by name pattern.",
	parameters = {
		type = "object",
		properties = {
			pattern = { type = "string", description = "Glob pattern (e.g. '**/*.luau', 'src/tools/*.luau', '*.toml')" },
			path = { type = "string", description = "Base directory to search in (default: '.')" },
			max_results = { type = "number", description = "Maximum number of results to return (default: 100)" },
		},
		required = { "pattern" },
	},
	execute = function(args)
		if not args.pattern then
			return "Error: pattern required"
		end

		local basePath = args.path or "."
		local maxResults = args.max_results or 100

		local safe, reason = isSafePath(basePath)
		if not safe then
			return "Security Error: " .. tostring(reason)
		end

		-- Also check pattern for path traversal
		local safePat, patReason = isSafePath(args.pattern)
		if not safePat then
			return "Security Error: " .. tostring(patReason)
		end

		local results = walkDir(basePath, args.pattern, maxResults)

		if #results == 0 then
			return "No files found matching pattern: " .. args.pattern
		end

		local output = table.concat(results, "\n")
		if #results >= maxResults then
			output ..= "\n\n... (truncated at " .. maxResults .. " results)"
		end

		return output
	end,
}

-- Export matchGlob for testing
Glob.matchGlob = matchGlob

return Glob
