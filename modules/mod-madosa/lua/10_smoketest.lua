--[[
    Smoke test: proves the ALE pipeline is actually live.

    Deliberately does nothing but log. If the line below is missing from ALE.log
    (or the console) after a start or a ".reload ALE", then the engine, the script
    path or the symlink is wrong - fix that before debugging any real script.

    Safe to delete once you trust the setup.
]]

local WORLD_EVENT_ON_STARTUP = 14

local function OnStartup(event)
    Madosa.Log("ALE is live - core=%s, bot account prefix=%q",
        tostring(GetCoreName()), Madosa.BOT_ACCOUNT_PREFIX)
end

RegisterServerEvent(WORLD_EVENT_ON_STARTUP, OnStartup)
