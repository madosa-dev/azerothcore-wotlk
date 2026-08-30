--[[
    Tell a player on login that they have an XP boost, and by how much.

    mod-xpboost stores the boost in character_xp_boost and (since the buff icon was
    wired up) shows spell 900001 while it is active. The icon alone does not say how
    large the boost is, and ".xpboost info" is GM-only, so without this a player has
    no way to see their own percentage.

    Why the bot guard matters: this realm runs ~3000 playerbots and login fires for
    every one of them. Without Madosa.IsRealPlayer() the query below would run
    thousands of times during a bot ramp-up. With it, it runs a handful of times -
    once per actual human - which is why a synchronous query is acceptable here.
]]

local PLAYER_EVENT_ON_LOGIN = 3

local function OnLogin(event, player)
    if not Madosa.IsRealPlayer(player) then
        return
    end

    -- pcall: if mod-xpboost's SQL was never applied the table does not exist, and a
    -- failed query should not take the login hook (or any later script) down with it.
    local ok, result = pcall(CharDBQuery,
        string.format("SELECT pct FROM character_xp_boost WHERE guid = %u", player:GetGUIDLow()))

    if not ok then
        Madosa.LogError("xpboost lookup failed (is character_xp_boost present?): %s", tostring(result))
        return
    end

    if not result then
        return -- no boost on this character, stay quiet
    end

    local pct = result:GetUInt32(0)
    if pct and pct > 0 then
        player:SendBroadcastMessage(string.format(
            "|cff1eff00XP Boost:|r you are gaining |cffffffff+%u%%|r bonus experience.", pct))
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
