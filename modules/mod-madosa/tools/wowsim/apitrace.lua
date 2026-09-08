-- Which parts of the client the harness has not got round to.
--
-- The API here is whatever addons have needed so far, not the whole of WoW,
-- and the honest way to run a new addon is to let it tell you what is missing
-- rather than to guess. Every read of an undefined global that looks like a
-- game API is counted, so after a run Sim.Missing() lists exactly what to add.
--
-- Reading a nil global is legal Lua and addons do it deliberately ("if
-- ElvUI then"), so this only records. Sim.Strict(true) turns a read into an
-- error instead, which is what to use once an addon is known to run: then a
-- new call site shows up immediately, with a traceback.

local missing, strict = {}, false

local function looksLikeApi(key)
    if type(key) ~= "string" then return false end
    if not key:match("^[A-Z]") then return false end
    return key:match("^[%u][%w_]*$") ~= nil
end

setmetatable(_G, {
    __index = function(_, key)
        if looksLikeApi(key) then
            missing[key] = (missing[key] or 0) + 1
            if strict then
                error("the harness has no " .. key .. "() - add it to client.lua", 2)
            end
        end
        return nil
    end,
})

function Sim.Strict(on) strict = on ~= false end

-- Something noticed a gap by other means - hooksecurefunc stubbing a function
-- that was not there - and wants it on the same list.
function Sim.NoteMissing(name) missing[name] = (missing[name] or 0) + 1 end

-- { {name, reads}, ... }, most-read first.
function Sim.Missing()
    local out = {}
    for name, count in pairs(missing) do out[#out + 1] = { name = name, reads = count } end
    table.sort(out, function(a, b)
        if a.reads ~= b.reads then return a.reads > b.reads end
        return a.name < b.name
    end)
    return out
end

function Sim.ForgetMissing() missing = {} end

function Sim.ReportMissing(printer)
    printer = printer or print
    local list = Sim.Missing()
    if #list == 0 then
        printer("every global the addon read is implemented")
        return list
    end
    printer(string.format("%d globals were read that the harness does not define:", #list))
    for _, entry in ipairs(list) do
        printer(string.format("  %-40s %d read%s", entry.name, entry.reads,
            entry.reads == 1 and "" or "s"))
    end
    return list
end
