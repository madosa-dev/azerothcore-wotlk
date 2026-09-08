-- The globals WoW adds on top of Lua 5.1.
--
-- The client exposes most of the string, table and math libraries as bare
-- globals, plus a handful of helpers of its own, and real addons use them
-- everywhere - LibStub calls strmatch on its second line. None of this is
-- game state, it is just the standard library the addon expects to find, so
-- it lives apart from client.lua.

-- string ------------------------------------------------------------------
strlen, strsub, strupper, strlower, strrep, strbyte, strchar =
    string.len, string.sub, string.upper, string.lower, string.rep,
    string.byte, string.char
strfind, strmatch, strgmatch, gsub, gmatch, format =
    string.find, string.match, string.gmatch, string.gsub, string.gmatch,
    string.format

function strtrim(s, chars)
    chars = chars or " \t\r\n"
    local pattern = "[" .. chars:gsub("(%W)", "%%%1") .. "]"
    return (tostring(s):gsub("^" .. pattern .. "+", ""):gsub(pattern .. "+$", ""))
end

-- strsplit returns the pieces as multiple values, not a table.
function strsplit(sep, text, limit)
    local out, pattern = {}, "[" .. sep:gsub("(%W)", "%%%1") .. "]"
    local start = 1
    while true do
        if limit and #out == limit - 1 then break end
        local from, to = text:find(pattern, start)
        if not from then break end
        out[#out + 1] = text:sub(start, from - 1)
        start = to + 1
    end
    out[#out + 1] = text:sub(start)
    return unpack(out)
end

function strjoin(sep, ...)
    return table.concat({ ... }, sep)
end
strconcat = function(...) return table.concat({ ... }) end

-- table -------------------------------------------------------------------
tinsert, tremove, sort, tsort = table.insert, table.remove, table.sort, table.sort
tconcat = table.concat

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
table.wipe = wipe

function getn(t) return #t end

-- Vanilla-era global accessors. Addons ported forward from 1.12 - pfQuest is
-- one - still use them everywhere.
function getglobal(name) return rawget(_G, name) end
function setglobal(name, value) rawset(_G, name, value) end
function TEXT(name) return rawget(_G, name) or name end

-- math --------------------------------------------------------------------
abs, ceil, floor, max, min, random, sqrt =
    math.abs, math.ceil, math.floor, math.max, math.min, math.random, math.sqrt
mod, fmod = math.fmod, math.fmod
PI = math.pi

-- WoW's sin/cos/tan take DEGREES, not radians - they are the client's own,
-- not math.sin. Addons that mix them up with a radian-valued angle get
-- nonsense, which is a real bug worth being able to reproduce here.
function sin(deg) return math.sin(math.rad(deg)) end
function cos(deg) return math.cos(math.rad(deg)) end
function tan(deg) return math.tan(math.rad(deg)) end
function asin(x) return math.deg(math.asin(x)) end
function acos(x) return math.deg(math.acos(x)) end
function atan(x) return math.deg(math.atan(x)) end
function atan2(y, x) return math.deg(math.atan2(y, x)) end
function log10(x) return math.log(x) / math.log(10) end

-- bit ---------------------------------------------------------------------
-- 3.3.5 ships a bit library; lua5.1 alone does not, so this is the plain
-- arithmetic version. Enough for the flag-testing addons do.
if not bit then
    local function tobits(x, n)
        local out = {}
        x = math.floor(x) % 2 ^ 32
        for i = 1, n do out[i] = x % 2; x = math.floor(x / 2) end
        return out
    end
    local function frombits(b)
        local x = 0
        for i = #b, 1, -1 do x = x * 2 + b[i] end
        return x
    end
    local function apply(a, b, fn)
        local x, y, out = tobits(a, 32), tobits(b, 32), {}
        for i = 1, 32 do out[i] = fn(x[i], y[i]) end
        return frombits(out)
    end
    bit = {
        band = function(a, b) return apply(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end,
        bor = function(a, b) return apply(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end,
        bxor = function(a, b) return apply(a, b, function(x, y) return x ~= y and 1 or 0 end) end,
        bnot = function(a) return (2 ^ 32 - 1) - (math.floor(a) % 2 ^ 32) end,
        lshift = function(a, n) return (math.floor(a) * 2 ^ n) % 2 ^ 32 end,
        rshift = function(a, n) return math.floor(math.floor(a) % 2 ^ 32 / 2 ^ n) end,
    }
end

-- the client's own helpers -------------------------------------------------

-- A monotonic clock; Sim.Tick moves it, so an addon that throttles on GetTime
-- sees time pass exactly as fast as the scenario says it does.
local clock = 0
function GetTime() return clock end
function Sim.Advance(seconds) clock = clock + (seconds or 0); return clock end

function GetLocale() return World and World.locale or "enUS" end
function GetBuildInfo() return "3.3.5", "12340", "2010-03-23", 30300 end
function GetCVar(name) return World and World.cvars and World.cvars[name] or nil end
function SetCVar(name, value)
    World.cvars = World.cvars or {}
    World.cvars[name] = value and tostring(value) or nil
    return true
end

function securecall(fn, ...)
    if type(fn) == "string" then fn = _G[fn] end
    return fn(...)
end
function issecure() return false end
function scrub(...) return ... end

-- The one hook addons genuinely rely on: run something after a function.
-- Hooking something the harness has not got is common - addons hook FrameXML
-- freely - and stopping the load over it would hide everything after. A stub
-- is put there instead and the name is recorded as missing, so the run keeps
-- going and Sim.ReportMissing still says what is not there.
function hooksecurefunc(owner, name, post)
    if post == nil then owner, name, post = _G, owner, name end
    local original = rawget(owner, name)
    if type(original) ~= "function" then
        original = function() end
        if owner == _G then Sim.NoteMissing(name) end
    end
    owner[name] = function(...)
        local result = { original(...) }
        post(...)
        return unpack(result)
    end
end

function debugstack(level) return debug.traceback("", (level or 1) + 1) end
function debugprofilestart() end
function debugprofilestop() return 0 end

local handler = function(err) print("|cffff2020error|r " .. tostring(err)) end
function geterrorhandler() return handler end
function seterrorhandler(fn) handler = fn end

function message(text) print(text) end
function PlaySound() end
function PlaySoundFile() end
function GetScreenWidth() return SCREEN.width end
function GetScreenHeight() return SCREEN.height end
function GetRealmName() return "Harness" end
function UnitName(unit) return unit == "player" and (World.playerName or "Tester") or nil end
function UnitGUID(unit) return unit == "player" and "0x0000000000000001" or nil end
function UnitFactionGroup() return World.faction or "Alliance", World.faction or "Alliance" end
function UnitRace() return World.race or "Orc", (World.race or "Orc"):upper() end
function UnitSex() return 2 end
function IsInGuild() return false end
function IsShiftKeyDown() return MODIFIED_CLICK == "SHIFT" end
function IsControlKeyDown() return MODIFIED_CLICK == "CTRL" end
function IsAltKeyDown() return MODIFIED_CLICK == "ALT" end

-- FrameXML odds and ends ---------------------------------------------------
-- Small functions from the client's own Lua that libraries call on their way
-- up. Anything with a real answer gets one out of World; the rest are the
-- no-ops they are in a client with nothing going on.

function IsLoggedIn() return World.loggedIn ~= false end
function IsAddOnLoaded(name) return Addons[name] ~= nil, Addons[name] ~= nil end
function GetNumAddOns()
    local n = 0
    for _ in pairs(Addons) do n = n + 1 end
    return n
end
function GetAddOnInfo(name)
    local toc = Addons[name]
    if not toc then return nil end
    return toc.name, toc.title, toc.notes, true, "SECURE"
end
function GetAddOnMetadata(name, key)
    local toc = Addons[name]
    return toc and toc.meta and (toc.meta[key] or toc.meta[key:gsub("^%l", string.upper)]) or nil
end
function LoadAddOn() return false, "DISABLED" end
function UIParentLoadAddOn() return false end
function IsAddOnLoadOnDemand() return false end

function InterfaceOptions_AddCategory(frame)
    World.optionPanels = World.optionPanels or {}
    World.optionPanels[#World.optionPanels + 1] = frame
    return frame
end
function InterfaceOptionsFrame_OpenToCategory() end
function InterfaceOptionsFrame_Show() end

function RegisterAddonMessagePrefix() return true end
function SendAddonMessage() end
function GetNumGroupMembers() return 0 end
function GetNumPartyMembers() return 0 end
function GetNumRaidMembers() return 0 end
function UnitInParty() return false end
function UnitInRaid() return false end
function UnitIsUnit(a, b) return a == b end
function UnitExists(unit) return unit == "player" end
function UnitAffectingCombat() return World.combat end
function InCinematic() return false end
function GetContainerNumFreeSlots() return 0, 0 end
function GetMoney() return World.money or 0 end
function GetSpellInfo(id)
    local spell = World.spells and World.spells[id]
    if not spell then return nil end
    return spell.name, spell.rank or "", spell.icon or "", spell.cost, nil, nil, nil, nil
end
function GetItemIcon() return "" end
function GetItemCount() return 0 end
