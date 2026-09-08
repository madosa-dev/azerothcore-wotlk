-- Loading an addon the way the client loads one.
--
-- An addon is a directory with a .toc: some `## Key: value` lines and then the
-- files to run, in order. That is all the client needs and all this needs.
-- SavedVariables named in the manifest are cleared before the addon runs, so
-- a test starts from a fresh character unless it sets them first, and
-- Sim.LoadAddon hands the manifest back so a test can assert on it.
--
-- Files are run in .toc order, Lua and XML alike - xml.lua handles the second
-- language. A UTF-8 byte order mark is stripped first, because the client
-- tolerates one and lua5.1 does not.

Addons = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function split(list)
    local out = {}
    for item in (list or ""):gmatch("[^,]+") do out[#out + 1] = trim(item) end
    return out
end

-- Parse a .toc into { title, interface, notes, author, version, saved,
-- savedPerCharacter, dependencies, optionalDeps, files, xml }.
function Sim.ParseToc(path)
    local fh = assert(io.open(path, "r"), "no .toc at " .. path)
    local toc = { files = {}, xml = {}, saved = {}, savedPerCharacter = {},
                  dependencies = {}, optionalDeps = {}, meta = {} }
    for line in fh:lines() do
        line = trim(line:gsub("\r", ""))
        local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
        if key then
            local lower = key:lower()
            toc.meta[key] = value
            if lower == "title" then toc.title = value
            elseif lower == "interface" then toc.interface = tonumber(value)
            elseif lower == "notes" then toc.notes = value
            elseif lower == "author" then toc.author = value
            elseif lower == "version" then toc.version = value
            elseif lower == "savedvariables" then toc.saved = split(value)
            elseif lower == "savedvariablespercharacter" then toc.savedPerCharacter = split(value)
            elseif lower == "dependencies" or lower == "requireddeps" then
                toc.dependencies = split(value)
            elseif lower == "optionaldeps" then toc.optionalDeps = split(value)
            end
        elseif line ~= "" and not line:match("^#") then
            local file = line:gsub("\\", "/")
            toc.files[#toc.files + 1] = file
            if file:lower():match("%.xml$") then toc.xml[#toc.xml + 1] = file end
        end
    end
    fh:close()
    return toc
end

local function fileExists(path)
    local fh = io.open(Sim.ResolvePath and Sim.ResolvePath(path) or path, "r")
    if fh then fh:close(); return true end
    return false
end

-- The client takes <folder>/<folder>.toc, but plenty of folders on disk are
-- named for where they came from - a checkout called ElvUI_RaidMarkers.repo
-- still holds ElvUI_RaidMarkers.toc - so fall back to the only .toc there is.
local function findToc(dir, name)
    local direct = dir .. "/" .. name .. ".toc"
    if fileExists(direct) then return direct end
    local found = {}
    local pipe = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    if pipe then
        for line in pipe:lines() do
            if line:lower():match("%.toc$") then found[#found + 1] = dir .. "/" .. line end
        end
        pipe:close()
    end
    if #found == 1 then return found[1] end
    return direct, #found > 1 and found or nil
end

-- Load an addon directory. Returns the manifest, or nil plus why not.
function Sim.LoadAddon(dir, opts)
    opts = opts or {}
    dir = dir:gsub("/$", "")
    local name = dir:match("([^/\\]+)$")
    local tocPath, ambiguous = opts.toc, nil
    if not tocPath then tocPath, ambiguous = findToc(dir, name) end
    if not fileExists(tocPath) then
        if ambiguous then
            return nil, dir .. " holds several .toc files (" .. table.concat(ambiguous, ", ")
                .. ") - name one with { toc = ... }"
        end
        return nil, "no " .. name .. ".toc in " .. dir
    end
    local toc = Sim.ParseToc(tocPath)
    toc.name, toc.dir = name, dir
    -- The client hands every file of an addon two varargs: the folder name and
    -- one table private to that addon. Nearly every modern addon opens with
    -- `local NAME, ns = ...`, so a harness that calls the chunk with nothing
    -- fails on line one.
    toc.private = {}
    Sim.loading = toc


    for _, dep in ipairs(toc.dependencies) do
        if not Addons[dep] then
            return nil, name .. " needs " .. dep .. ", which is not loaded"
        end
    end

    -- SavedVariables arrive as whatever the last session left, or nil on a
    -- fresh character; a test that wants a returning character sets them
    -- before calling this.
    for _, list in ipairs({ toc.saved, toc.savedPerCharacter }) do
        for _, var in ipairs(list) do
            if _G[var] == nil then _G[var] = nil end
        end
    end

    for _, file in ipairs(toc.files) do
        local path = dir .. "/" .. file
        if not fileExists(path) then
            return nil, name .. ": " .. file .. " is in the .toc but not on disk"
        end
        if file:lower():match("%.xml$") then
            if not opts.ignoreXml then
                local ok, err = Sim.LoadXml(path, path:match("^(.*)[/\\]"))
                if not ok then return nil, name .. " (" .. file .. "): " .. tostring(err) end
            end
        else
            -- read and compile rather than loadfile, so a UTF-8 byte order
            -- mark - which the client tolerates and lua5.1 does not - is not
            -- mistaken for a syntax error
            local body = Sim.ReadFile(path)
            local chunk, err = loadstring(body, "@" .. path)
            if not chunk then return nil, name .. ": " .. tostring(err) end
            local ok, runErr = pcall(chunk, name, toc.private)
            if not ok then return nil, name .. " (" .. file .. "): " .. tostring(runErr) end
        end
    end

    Sim.loading = nil
    Addons[name] = toc
    return toc
end

-- Everything the client fires at an addon on the way in, in order.
function Sim.Enter(...)
    for _, event in ipairs({ "ADDON_LOADED", "SPELLS_CHANGED", "PLAYER_LOGIN",
                             "PLAYER_ENTERING_WORLD" }) do
        Sim.Event(event, ...)
    end
    Sim.Tick()
end

-- The talent tree arriving from the server, which on 3.3.5 happens a moment
-- after login and carries no event of its own worth relying on.
function Sim.TalentsArrive()
    World.talentsLoaded = true
    Sim.Event("PLAYER_TALENT_UPDATE")
    Sim.Tick()
end
