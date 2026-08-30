--[[
    Shared helpers for this server's ALE scripts.

    Loaded first: ALE sorts scripts by file path (LuaEngine.cpp ScriptPathComparator)
    and all scripts share one Lua state, so the "00_" prefix guarantees the globals
    below exist by the time any other script here runs.

    NOTE: ALE is NOT Eluna. It is a diverged fork with its own API - scripts written
    for the original Eluna project will not run here, and vice versa. Check the real
    method names in modules/mod-ale/src/LuaEngine/LuaFunctions.cpp before using
    anything you found in an Eluna tutorial.
]]

Madosa = Madosa or {}

local BOT_ACCOUNT_PREFIX_FALLBACK = "rndbot"

-- Read once at load: the prefix mod-playerbots gives its random bot accounts.
-- Module configs share the core's ConfigMgr, so this resolves even though it lives
-- in playerbots.conf rather than worldserver.conf.
local botPrefix = GetConfigValue("AiPlayerbot.RandomBotAccountPrefix")
if type(botPrefix) ~= "string" or botPrefix == "" then
    botPrefix = BOT_ACCOUNT_PREFIX_FALLBACK
end
Madosa.BOT_ACCOUNT_PREFIX = string.lower(botPrefix)

--[[
    True for a mod-playerbots random bot, false for a human.

    This matters more here than on a normal server: this realm runs ~3000 bots, so
    player-scoped hooks (login, XP, level up) fire overwhelmingly for bots. Anything
    doing real work per player - a DB query above all - must skip them, or a bot
    ramp-up turns into thousands of queries.

    Detection is by account name prefix because that is what mod-playerbots itself
    keys on; ALE exposes no bot-awareness of its own.
]]
function Madosa.IsPlayerbot(player)
    if not player then
        return false
    end

    local account = player:GetAccountName()
    if type(account) ~= "string" then
        return false
    end

    return string.sub(string.lower(account), 1, #Madosa.BOT_ACCOUNT_PREFIX) == Madosa.BOT_ACCOUNT_PREFIX
end

-- Convenience inverse, so callers read as intent rather than negation.
function Madosa.IsRealPlayer(player)
    return player ~= nil and not Madosa.IsPlayerbot(player)
end

-- Tagged logging, so this server's script output is greppable in ALE.log.
function Madosa.Log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    PrintInfo("[madosa] " .. (ok and msg or tostring(fmt)))
end

function Madosa.LogError(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    PrintError("[madosa] " .. (ok and msg or tostring(fmt)))
end
