-- MapsterDrag: drag the world map by its map area.
--
-- Mapster already makes WorldMapFrame movable (SetMovable, RegisterForDrag,
-- OnDragStart -> wmfStartMoving in mapster.lua). The trouble is reaching it:
-- WorldMapButton, the map surface itself, covers nearly the whole frame and
-- eats the mouse, and Mapster hides WorldMapTitleButton - the strip Blizzard
-- meant you to drag. What is left is a few pixels of border, and with
-- Mapster's "hide border" option on, effectively nothing.
--
-- So this forwards drags on the map surface to the frame's own handlers. It
-- deliberately reuses Mapster's scripts rather than calling StartMoving()
-- directly, because Mapster hides the quest blobs while the frame moves (they
-- are drawn in screen space and would otherwise smear across the map).
--
-- Left-drag is free in WotLK: the world map has no drag gesture of its own, and
-- RegisterForDrag only fires past the drag threshold, so ordinary clicks on
-- quest POIs still register as clicks.

local ADDON = "MapsterDrag"

MapsterDragDB = MapsterDragDB or {}

local function mapsterHandler(script)
    -- Mapster sets these on WorldMapFrame; nil until Mapster has initialised.
    return WorldMapFrame and WorldMapFrame:GetScript(script)
end

local function onDragStart()
    if not WorldMapFrame or not WorldMapFrame:IsMovable() then return end
    if MapsterDragDB.disabled then return end

    local handler = mapsterHandler("OnDragStart")
    if handler then
        handler(WorldMapFrame)          -- Mapster: HideBlobs() + StartMoving()
    else
        WorldMapFrame:StartMoving()     -- Mapster gone or changed: still usable
    end
end

local function onDragStop()
    if not WorldMapFrame then return end

    local handler = mapsterHandler("OnDragStop")
    if handler then
        handler(WorldMapFrame)          -- Mapster: StopMoving + SavePosition + ShowBlobs
    else
        WorldMapFrame:StopMovingOrSizing()
    end
end

local function install()
    if not WorldMapButton then return false end

    -- Do not clobber someone else's drag handling.
    if WorldMapButton:GetScript("OnDragStart") then return false end

    WorldMapButton:RegisterForDrag("LeftButton")
    WorldMapButton:SetScript("OnDragStart", onDragStart)
    WorldMapButton:SetScript("OnDragStop", onDragStop)
    return true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if not install() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ADDON ..
            "|r: could not attach to the world map (WorldMapButton missing or " ..
            "already handled by another addon).")
    end
end)

SLASH_MAPSTERDRAG1 = "/mapsterdrag"
SLASH_MAPSTERDRAG2 = "/mdrag"
SlashCmdList["MAPSTERDRAG"] = function()
    MapsterDragDB.disabled = not MapsterDragDB.disabled
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. ADDON .. "|r: map dragging " ..
        (MapsterDragDB.disabled and "off" or "on") .. ".")
end
