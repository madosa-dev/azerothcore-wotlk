-- VanityQuality: recolors item quality 6 into a "Vanity" quality.
--
-- WotLK 3.3.5a never assigns quality 6 ("Artifact") to any obtainable item -
-- it predates the systems that would have used it - so mod-madosa repurposes
-- it for account-wide companions/toys (item_template.Quality = 6) instead of
-- inventing an out-of-range value the client has never seen.
--
-- The quality's RGB comes from the native GetItemQualityColor(quality) call,
-- not from an editable data file, so it can't be changed with a client patch
-- (MPQ/DBC) the way the pet models are. It CAN be changed from Lua: FrameXML
-- populates ITEM_QUALITY_COLORS[6] by calling GetItemQualityColor(6) once at
-- login, and reads straight from that table afterwards (LootFrame.lua,
-- UnitPopup.lua), so overwriting the table entry covers those. A few frames
-- (ContainerFrame.lua's bag icon borders, MailFrame.lua) call
-- GetItemQualityColor(quality) fresh every time instead of using the cached
-- table, so the global function itself is wrapped too - Lua resolves a global
-- function call by name at call time, so every one of those call sites picks
-- up the override automatically without touching FrameXML.
--
-- Known gap: anything the engine renders without going through Lua at all -
-- the ground glow on dropped loot, the tooltip's item name/border - keeps the
-- native Artifact gold, since that path never calls back into Lua. Not fixable
-- without patching the client executable itself.

local VANITY_QUALITY = 6
local R, G, B = 0.90, 0.30, 1.00
local HEX = "|cffe64dff"

ITEM_QUALITY6_DESC = "Vanity"

if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[VANITY_QUALITY] then
    ITEM_QUALITY_COLORS[VANITY_QUALITY].r = R
    ITEM_QUALITY_COLORS[VANITY_QUALITY].g = G
    ITEM_QUALITY_COLORS[VANITY_QUALITY].b = B
    ITEM_QUALITY_COLORS[VANITY_QUALITY].hex = HEX
end

local BlizzardGetItemQualityColor = GetItemQualityColor
function GetItemQualityColor(quality, ...)
    if quality == VANITY_QUALITY then
        return R, G, B, HEX
    end
    return BlizzardGetItemQualityColor(quality, ...)
end
