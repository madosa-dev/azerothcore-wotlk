-- WorldforgedAtlas: mod-madosa's Ascension Worldforged finds, on the map.
--
-- The server holds 1633 fixed Worldforged spots and streams a cache in when a
-- real player walks near one (mod_madosa_worldforged_ascension.cpp). Nothing
-- announces them, so without a map the only way to find one is to walk over it.
-- This is the Ascension LootCollector's job, done from the server's own data:
-- Data.lua is generated straight out of the spawn table, so a pin is a place a
-- cache actually stands.
--
-- Claimed finds
-- -------------
-- Each Worldforged item may be claimed once per character, and the interesting
-- part of the map is what you have *not* had yet. Only the server knows that, so
-- the addon asks for the list on login over the same self-whisper + LANG_ADDON
-- bridge MadosaControl uses, on its own prefix and with no permission gate -
-- every player needs their own collection. The answer is cached per character,
-- so the map is already right on the next login before the sync arrives, and a
-- claim made this session is pushed as it happens.
--
-- Placement is Astrolabe's
-- ------------------------
-- Data.lua stores zone-relative fractions, which are only meaningful on that
-- one zone map. Astrolabe translates them onto whatever map is open - zone,
-- continent or the world - and keeps minimap pins positioned as the player
-- moves, so neither of those is reimplemented here. Without Astrolabe the addon
-- still draws zone maps correctly and simply leaves the minimap alone.
--
-- Mapster is not involved: it rescales and reskins WorldMapFrame, and pins are
-- children of WorldMapDetailFrame, so they follow it wherever it goes.

local _, ns = ...

local ADDON_PREFIX = "WFATLAS"
local FIELD_SEP = "~"

-- A continent map already carries every zone's pins at once. The cap is a guard
-- against a pathological case, not an expected limit: Eastern Kingdoms, the
-- busiest map, comes to about 800.
local MAX_WORLD_PINS = 1200

local PIN_SIZE = 14
local MINIMAP_PIN_SIZE = 11
local PIN_BORDER = 3

-- A pin wears the icon of the item lying under it, so the map says what is
-- there and not merely that something is. GetItemIcon() answers from the
-- client's item cache and returns nothing for an item this character has never
-- been shown, which is most of them on a fresh install - hence the fallback, and
-- hence re-asking on every refresh until it answers.
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local Astrolabe = DongleStub and DongleStub("Astrolabe-0.4")

WorldforgedAtlasDB = WorldforgedAtlasDB or {}

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------

local defaults = {
    enabled = true,
    minimap = true,
    hideClaimed = true,
    continentPins = true,
    minQuality = 0,      -- 0 shows everything; 4 shows epics only
    claimed = {},        -- item id -> true, as the server last reported it
}

local function ApplyDefaults()
    for key, value in pairs(defaults) do
        if WorldforgedAtlasDB[key] == nil then
            WorldforgedAtlasDB[key] = (type(value) == "table") and {} or value
        end
    end
end

local db = WorldforgedAtlasDB

----------------------------------------------------------------------------
-- Zone index
----------------------------------------------------------------------------

-- Zone name -> the continent/zone pair SetMapZoom and Astrolabe both speak.
-- Built by walking the client's own zone lists rather than shipped in Data.lua,
-- because those indices are the client's business and shift between builds,
-- while the zone *name* is what the server's spawn table records.
local zoneIndex = {}

local function BuildZoneIndex()
    local continents = { GetMapContinents() }
    for c = 1, #continents do
        local zones = { GetMapZones(c) }
        for z = 1, #zones do
            zoneIndex[zones[z]] = { c = c, z = z }
        end
    end
end

----------------------------------------------------------------------------
-- Filtering
----------------------------------------------------------------------------

local function ItemInfo(itemID)
    return ns.items[itemID]
end

-- Everything the pin lists have to agree on: the map, the minimap and the
-- counter must never disagree about whether a spot is worth showing.
local function IsVisible(itemID)
    if db.hideClaimed and db.claimed[itemID] then return false end

    local info = ItemInfo(itemID)
    if not info then return false end
    if db.minQuality > 0 and info[2] < db.minQuality then return false end

    return true
end

-- Pins for one zone, as an iterator over (across, down, itemID). Data.lua stores
-- flat triples, so this is where the stride is known and nowhere else.
local function ZonePoints(entry)
    local points, i = entry.points, -2
    return function()
        i = i + 3
        if i > #points then return nil end
        return points[i], points[i + 1], points[i + 2]
    end
end

local function ZoneCounts(entry)
    local shown, total = 0, 0
    for _, _, itemID in ZonePoints(entry) do
        total = total + 1
        if not db.claimed[itemID] then shown = shown + 1 end
    end
    return shown, total
end

----------------------------------------------------------------------------
-- Pins
----------------------------------------------------------------------------

local worldPins, worldPinsUsed = {}, 0
local minimapPins, minimapPinsUsed = {}, 0

local function PinTooltip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")

    local info = ItemInfo(pin.itemID)
    local name = info and info[1] or ("Item " .. pin.itemID)
    local color = info and ITEM_QUALITY_COLORS[info[2]] or ITEM_QUALITY_COLORS[1]

    GameTooltip:AddLine(name, color.r, color.g, color.b)
    if info then
        local slot = ns.slotNames[info[4]]
        GameTooltip:AddLine(string.format("Item Level %d%s", info[3],
            slot and (" - " .. slot) or ""), 0.8, 0.8, 0.8)
    end

    if db.claimed[pin.itemID] then
        GameTooltip:AddLine("Already claimed on this character", 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine("Worldforged - not yet claimed", 0.1, 1.0, 0.1)
    end

    -- The real tooltip, if the client has the item cached; the server sends it
    -- on first sight, so this fills in a moment after the first hover.
    local link = select(2, GetItemInfo(pin.itemID))
    if link then
        GameTooltip:AddLine(" ")
        GameTooltip:SetHyperlink(link)
    end

    GameTooltip:Show()
end

local function AcquirePin(pool, used, parent, size)
    local pin = pool[used]
    if not pin then
        pin = CreateFrame("Frame", nil, parent)
        pin:SetWidth(size)
        pin:SetHeight(size)
        pin:EnableMouse(true)

        -- A solid colour drawn one pin-border larger than the icon, which reads
        -- as a quality-coloured ring around it without needing an art file.
        local border = pin:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -PIN_BORDER, PIN_BORDER)
        border:SetPoint("BOTTOMRIGHT", PIN_BORDER, -PIN_BORDER)
        pin.border = border

        local icon = pin:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(pin)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim the icon's own border
        pin.icon = icon

        -- The handlers read pin.itemID off the frame they are called with, so
        -- they are set once here rather than re-hooked on every refresh.
        pin:SetScript("OnEnter", PinTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

        pool[used] = pin
    end
    pin:SetParent(parent)
    return pin
end

local function DressPin(pin, itemID)
    pin.itemID = itemID
    pin.icon:SetTexture(GetItemIcon(itemID) or FALLBACK_ICON)

    local info = ItemInfo(itemID)
    local color = info and ITEM_QUALITY_COLORS[info[2]]
    if color then
        pin.border:SetTexture(color.r, color.g, color.b)
    else
        pin.border:SetTexture(0, 0, 0)
    end

    -- A claimed find is left on the map when the filter is off, but faded, so
    -- what is still out there stands out at a glance.
    pin:SetAlpha(db.claimed[itemID] and 0.35 or 1.0)
end

local function HideFrom(pool, from)
    for i = from, #pool do
        if pool[i] then pool[i]:Hide() end
    end
end

-- Astrolabe's own RemoveAllMinimapIcons() drops every icon the library is
-- tracking, which on this client means Questie's and everyone else's as well.
-- Only this addon's pins are ever handed back.
local function ReleaseMinimapPins(from)
    for i = from, #minimapPins do
        local pin = minimapPins[i]
        if pin then
            if Astrolabe then Astrolabe:RemoveIconFromMinimap(pin) end
            pin:Hide()
        end
    end
end

----------------------------------------------------------------------------
-- World map
----------------------------------------------------------------------------

local statusText

local function UpdateWorldMap()
    worldPinsUsed = 0

    if not db.enabled or not WorldMapFrame:IsShown() then
        HideFrom(worldPins, 1)
        return
    end

    local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone()
    local texture = GetMapInfo()
    local onZoneMap = (zone and zone > 0)

    -- Cosmic and Azeroth (continent 0 / -1) would put every pin in the world on
    -- one screen, which is not a map any more.
    if not continent or continent < 1 then
        HideFrom(worldPins, 1)
        if statusText then statusText:SetText("") end
        return
    end
    if not onZoneMap and not db.continentPins then
        HideFrom(worldPins, 1)
        if statusText then statusText:SetText("") end
        return
    end

    local shownHere, totalHere = 0, 0

    for _, entry in ipairs(ns.zones) do
        local index = zoneIndex[entry.zone]

        -- Only the zones that can actually land on the map being looked at: the
        -- one zone on a zone map, this continent's zones on a continent map.
        -- Astrolabe would reject the rest anyway, but not before each had taken
        -- a frame out of the pool and a slot off MAX_WORLD_PINS - and since the
        -- zone list is alphabetical, the two continents interleave, so the cap
        -- would cut into the pins actually being looked at.
        local relevant = index and (onZoneMap and entry.texture == texture
                                            or not onZoneMap and index.c == continent)

        if relevant then
            for across, down, itemID in ZonePoints(entry) do
                if IsVisible(itemID) then
                    if worldPinsUsed >= MAX_WORLD_PINS then break end
                    worldPinsUsed = worldPinsUsed + 1

                    local pin = AcquirePin(worldPins, worldPinsUsed, WorldMapDetailFrame, PIN_SIZE)
                    DressPin(pin, itemID)

                    if Astrolabe then
                        Astrolabe:PlaceIconOnWorldMap(WorldMapDetailFrame, pin,
                            index.c, index.z, across, down)
                    elseif onZoneMap then
                        -- Without Astrolabe the fractions are still exactly right
                        -- for their own zone map; only the continent view needs
                        -- translating, and that is given up.
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT",
                            across * WorldMapDetailFrame:GetWidth(),
                            -down * WorldMapDetailFrame:GetHeight())
                        pin:Show()
                    else
                        pin:Hide()
                    end
                end
            end

            if onZoneMap then
                shownHere, totalHere = ZoneCounts(entry)
            end
        end
    end

    HideFrom(worldPins, worldPinsUsed + 1)

    if statusText then
        if onZoneMap then
            statusText:SetText(string.format("|cffffd100%d|r of %d left here", shownHere, totalHere))
        else
            statusText:SetText(string.format("|cffffd100%d|r pins on this map", worldPinsUsed))
        end
    end
end

----------------------------------------------------------------------------
-- Minimap
----------------------------------------------------------------------------

-- Astrolabe keeps placed minimap icons positioned on its own, so this only has
-- to run when the set of pins changes - a zone change, a claim, a filter - and
-- not on every frame.
local function UpdateMinimap()
    minimapPinsUsed = 0

    if not Astrolabe or not db.enabled or not db.minimap then
        ReleaseMinimapPins(1)
        return
    end

    local zoneName = GetRealZoneText()
    local index = zoneIndex[zoneName]
    if not index then
        ReleaseMinimapPins(1)
        return
    end

    for _, entry in ipairs(ns.zones) do
        if entry.zone == zoneName then
            for across, down, itemID in ZonePoints(entry) do
                if IsVisible(itemID) then
                    minimapPinsUsed = minimapPinsUsed + 1

                    local pin = AcquirePin(minimapPins, minimapPinsUsed, Minimap, MINIMAP_PIN_SIZE)
                    DressPin(pin, itemID)
                    Astrolabe:PlaceIconOnMinimap(pin, index.c, index.z, across, down)
                end
            end
            break
        end
    end

    ReleaseMinimapPins(minimapPinsUsed + 1)
end

local function Refresh()
    UpdateWorldMap()
    UpdateMinimap()
end

----------------------------------------------------------------------------
-- Comm
----------------------------------------------------------------------------

local syncing = nil

local function RequestSync()
    local player = UnitName("player")
    if player and player ~= "" then
        SendAddonMessage(ADDON_PREFIX, "SYNC", "WHISPER", player)
    end
end

local function HandleMessage(message)
    local sep = string.find(message, FIELD_SEP, 1, true)
    local opcode = sep and string.sub(message, 1, sep - 1) or message
    local payload = sep and string.sub(message, sep + 1) or ""

    if opcode == "BEGIN" then
        -- Collected into a fresh table and swapped in at END, so an interrupted
        -- sync leaves the cached list from last login rather than half of one.
        syncing = {}

    elseif opcode == "CLAIMED" then
        if syncing then
            for id in string.gmatch(payload, "[^" .. FIELD_SEP .. "]+") do
                syncing[tonumber(id)] = true
            end
        end

    elseif opcode == "END" then
        if syncing then
            db.claimed = syncing
            syncing = nil
            Refresh()
        end

    elseif opcode == "CLAIM" then
        local id = tonumber(payload)
        if id then
            db.claimed[id] = true
            Refresh()
        end
    end
end

----------------------------------------------------------------------------
-- The panel on the world map
----------------------------------------------------------------------------

local function BuildPanel()
    local panel = CreateFrame("Frame", "WorldforgedAtlasPanel", WorldMapFrame)
    panel:SetWidth(190)
    panel:SetHeight(112)
    panel:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -20, -60)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    panel:SetFrameStrata("HIGH")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Worldforged")

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPRIGHT", -12, -10)

    local function Checkbox(name, label, y, key)
        local box = CreateFrame("CheckButton", "WorldforgedAtlas" .. name, panel, "UICheckButtonTemplate")
        box:SetWidth(22)
        box:SetHeight(22)
        box:SetPoint("TOPLEFT", 10, y)
        _G[box:GetName() .. "Text"]:SetText(label)
        _G[box:GetName() .. "Text"]:SetFontObject("GameFontHighlightSmall")
        box:SetChecked(db[key])
        box:SetScript("OnClick", function(self)
            db[key] = self:GetChecked() and true or false
            Refresh()
        end)
        return box
    end

    Checkbox("HideClaimed", "Hide claimed", -26, "hideClaimed")
    Checkbox("Minimap", "Minimap pins", -46, "minimap")
    Checkbox("Continent", "Continent maps", -66, "continentPins")

    local quality = CreateFrame("Frame", "WorldforgedAtlasQuality", panel, "UIDropDownMenuTemplate")
    quality:SetPoint("TOPLEFT", -6, -86)
    UIDropDownMenu_SetWidth(quality, 130)

    local qualities = { [0] = "Any quality", [2] = "Uncommon+", [3] = "Rare+", [4] = "Epic+" }
    local order = { 0, 2, 3, 4 }

    UIDropDownMenu_Initialize(quality, function()
        for _, value in ipairs(order) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = qualities[value]
            info.value = value
            info.checked = (db.minQuality == value)
            info.func = function(self)
                db.minQuality = self.value
                UIDropDownMenu_SetText(quality, qualities[self.value])
                Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(quality, qualities[db.minQuality] or qualities[0])

    return panel
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local panel

local function ShowPanel()
    if not panel then return end
    if db.enabled and WorldMapFrame:IsShown() then panel:Show() else panel:Hide() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("WORLD_MAP_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")

-- WORLD_MAP_UPDATE fires repeatedly while the map is open, and a continent map
-- is several hundred pins to reposition. Coalesce into one rebuild per frame
-- rather than one per event.
local pending = false

frame:SetScript("OnUpdate", function()
    if pending then
        pending = false
        UpdateWorldMap()
    end
end)

local synced = false

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "WorldforgedAtlas" then
            ApplyDefaults()
            db = WorldforgedAtlasDB
            BuildZoneIndex()
            panel = BuildPanel()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The zone lists are empty until the world is loaded, so the index built
        -- at ADDON_LOADED can come out short; rebuilding here costs nothing.
        BuildZoneIndex()
        if not synced then
            synced = true
            RequestSync()
        end
        Refresh()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateMinimap()

    elseif event == "WORLD_MAP_UPDATE" then
        ShowPanel()
        pending = true

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message = ...
        if prefix == ADDON_PREFIX then
            HandleMessage(message)
        end
    end
end)

----------------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------------

SLASH_WORLDFORGEDATLAS1 = "/worldforged"
SLASH_WORLDFORGEDATLAS2 = "/wfa"
SlashCmdList["WORLDFORGEDATLAS"] = function(input)
    input = string.lower(strtrim(input or ""))

    if input == "sync" then
        RequestSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WorldforgedAtlas|r: asking the server for your finds.")
        return
    end

    if input == "off" or input == "on" then
        db.enabled = (input == "on")
    else
        db.enabled = not db.enabled
    end

    ShowPanel()
    Refresh()

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WorldforgedAtlas|r: pins " ..
        (db.enabled and "shown." or "hidden."))
end
