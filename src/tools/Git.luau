--!strict
local process = require("@lune/process")

local Git = {}

-- Helper: run a git command and return output
local function runGit(args: {string}): (boolean, string)
    local ok, result = pcall(function()
        return process.spawn("git", args)
    end)

    if not ok then
        return false, "Error: git not available: " .. tostring(result)
    end

    if result.ok then
        return true, result.stdout
    else
        -- Git sometimes writes useful info to stderr (e.g. "nothing to commit")
        local output = result.stdout
        if #output == 0 then output = result.stderr end
        return false, output
    end
end

-- ═══════════════════════════════════════
--  git_status
-- ═══════════════════════════════════════

Git.statusTool = {
    name = "git_status",
    description = "Show the working tree status. Returns staged, unstaged, and untracked files in a structured format. Much faster than running 'run_command git status'.",
    parameters = {
        type = "object",
        properties = {
            short = { type = "boolean", description = "Use short format (default: false)" },
        },
        required = {},
    },
    execute = function(args)
        local gitArgs = { "status" }
        if args.short then
            table.insert(gitArgs, "--short")
        end
        table.insert(gitArgs, "--branch")

        local ok, output = runGit(gitArgs)
        if ok then
            if #output == 0 then return "Nothing to report." end
            return output
        else
            return "Error: " .. output
        end
    end,
}

-- ═══════════════════════════════════════
--  git_diff
-- ═══════════════════════════════════════

Git.diffTool = {
    name = "git_diff",
    description = "Show changes between commits, staging area, and working tree. By default shows unstaged changes. Use staged=true for staged changes, or provide a target (branch/commit) to diff against.",
    parameters = {
        type = "object",
        properties = {
            staged = { type = "boolean", description = "Show staged changes instead of unstaged (default: false)" },
            target = { type = "string", description = "Branch or commit to diff against (e.g. 'main', 'HEAD~3')" },
            path = { type = "string", description = "Limit diff to a specific file or directory" },
            stat = { type = "boolean", description = "Show diffstat summary only (default: false)" },
        },
        required = {},
    },
    execute = function(args)
        local gitArgs = { "diff" }

        if args.staged then
            table.insert(gitArgs, "--cached")
        end

        if args.stat then
            table.insert(gitArgs, "--stat")
        end

        if args.target then
            table.insert(gitArgs, args.target)
        end

        if args.path then
            table.insert(gitArgs, "--")
            table.insert(gitArgs, args.path)
        end

        local ok, output = runGit(gitArgs)
        if ok then
            if #output == 0 then return "No changes." end
            -- Truncate very large diffs
            if #output > 16000 then
                output = output:sub(1, 16000) .. "\n\n... (diff truncated at 16000 chars)"
            end
            return output
        else
            return "Error: " .. output
        end
    end,
}

-- ═══════════════════════════════════════
--  git_log
-- ═══════════════════════════════════════

Git.logTool = {
    name = "git_log",
    description = "Show commit history. Returns formatted log entries with hash, author, date, and message.",
    parameters = {
        type = "object",
        properties = {
            count = { type = "number", description = "Number of commits to show (default: 10)" },
            oneline = { type = "boolean", description = "One line per commit (default: false)" },
            path = { type = "string", description = "Show commits affecting this file/directory" },
            author = { type = "string", description = "Filter by author name/email" },
            since = { type = "string", description = "Show commits after date (e.g. '2024-01-01', '1 week ago')" },
        },
        required = {},
    },
    execute = function(args)
        local gitArgs = { "log" }
        local count = args.count or 10

        table.insert(gitArgs, "-n")
        table.insert(gitArgs, tostring(count))

        if args.oneline then
            table.insert(gitArgs, "--oneline")
        else
            table.insert(gitArgs, "--format=%h %an (%ar) %s")
        end

        if args.author then
            table.insert(gitArgs, "--author=" .. args.author)
        end

        if args.since then
            table.insert(gitArgs, "--since=" .. args.since)
        end

        if args.path then
            table.insert(gitArgs, "--")
            table.insert(gitArgs, args.path)
        end

        local ok, output = runGit(gitArgs)
        if ok then
            if #output == 0 then return "No commits found." end
            return output
        else
            return "Error: " .. output
        end
    end,
}

-- ═══════════════════════════════════════
--  git_commit
-- ═══════════════════════════════════════

Git.commitTool = {
    name = "git_commit",
    description = "Stage files and create a git commit. Specify files to stage, or use stage_all=true. Refuses to force-push or use dangerous flags.",
    parameters = {
        type = "object",
        properties = {
            message = { type = "string", description = "Commit message" },
            files = { type = "array", items = { type = "string" }, description = "Files to stage before committing (optional if stage_all=true)" },
            stage_all = { type = "boolean", description = "Stage all modified/deleted files (git add -A) before committing (default: false)" },
        },
        required = { "message" },
    },
    execute = function(args)
        if not args.message or #args.message == 0 then
            return "Error: commit message required"
        end

        -- Stage files
        if args.stage_all then
            local ok, out = runGit({ "add", "-A" })
            if not ok then return "Error staging files: " .. out end
        elseif args.files and #args.files > 0 then
            local addArgs = { "add" }
            for _, f in ipairs(args.files) do
                table.insert(addArgs, f)
            end
            local ok, out = runGit(addArgs)
            if not ok then return "Error staging files: " .. out end
        end

        -- Commit
        local ok, output = runGit({ "commit", "-m", args.message })
        if ok then
            return output
        else
            -- "nothing to commit" comes through stderr
            if output:find("nothing to commit") then
                return "Nothing to commit — working tree clean."
            end
            return "Error: " .. output
        end
    end,
}

return Git
