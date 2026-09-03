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
-- Pins go under WorldMapButton, not WorldMapDetailFrame
-- ----------------------------------------------------
-- The obvious parent is WorldMapDetailFrame, the frame holding the map art.
-- Pins parented there draw correctly and never receive a mouse event, because
-- WorldMapButton covers the whole map on top of it and takes them all - which
-- looks exactly like a broken tooltip and is not. Blizzard's own POIs and every
-- map addon on this client parent to WorldMapButton for that reason; the
-- *anchor* stays WorldMapDetailFrame, since that is the frame whose size the
-- fractions are relative to.
--
-- Two kinds of map, two kinds of marker
-- -------------------------------------
-- On a *zone* map the individual spot is the whole point, so every find gets
-- its own pin; they are bucketed into a grid one pin wide first, so two finds
-- a few yards apart become one marker with a count instead of two icons drawn
-- on top of each other. A grid rather than true proximity clustering: one pass
-- instead of n-squared, on a refresh that runs whenever the map updates, and
-- the seam where two points fall either side of a cell boundary costs one extra
-- marker nobody will notice.
--
-- On a *continent* map the individual spot is meaningless - it is a few pixels
-- across - and drawing them all was what made the first version unusable: 753
-- icons over Kalimdor, stacked four deep. Grid clustering does not save it
-- either, because the points are genuinely spread out; it only makes the wall
-- slightly thinner. So a continent shows **one marker per zone**, at the middle
-- of that zone's finds, carrying the count and listing what is there. That is
-- also the question actually being asked at that zoom - not "where exactly" but
-- "which zone is worth going to".
--
-- Astrolabe does the translation - a zone fraction is only meaningful on that
-- one zone map, and it knows how to put it on a continent. Without Astrolabe
-- the addon still draws zone maps correctly and leaves the rest alone.
--
-- Everything else is in a right-click menu on one small button in the map's
-- header bar, next to Zoom Out. A panel floating over the map hid the part of
-- the map it sat on, which for a map addon is a poor trade.
--
-- Mapster is not involved: it rescales and reskins WorldMapFrame, and the pins
-- are anchored to frames inside it, so they follow wherever it puts them.

local _, ns = ...

local ADDON_PREFIX = "WFATLAS"
local FIELD_SEP = "~"

local PIN_SIZE = 13
local MINIMAP_PIN_SIZE = 11
local PIN_BORDER = 2

-- Grid cell for clustering, in screen pixels. Slightly larger than a pin, so
-- two markers never touch.
local CLUSTER_PX = 16

-- Enough rows that a dense cluster is described rather than merely counted,
-- few enough that the tooltip stays on screen.
local TOOLTIP_ITEMS = 12

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
    -- Off by default: a continent carries every zone's finds at once, and even
    -- clustered that is a busier map than it is a useful one.
    continentPins = false,
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
-- counts must never disagree about whether a spot is worth showing.
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

-- Counted in distinct items, not in spots. Claiming is per item - taking a
-- Silverbound Dagger at one spot finishes every other spot holding one - so
-- "how many are left here" can only honestly mean how many things there are
-- still to collect, and several places in a zone hold the same item.
local function ZoneCounts(entry)
    local seen, shown, total = {}, 0, 0
    for _, _, itemID in ZonePoints(entry) do
        if not seen[itemID] then
            seen[itemID] = true
            total = total + 1
            if not db.claimed[itemID] then shown = shown + 1 end
        end
    end
    return shown, total
end

local function ZoneEntryForTexture(texture)
    for _, entry in ipairs(ns.zones) do
        if entry.texture == texture then return entry end
    end
end

----------------------------------------------------------------------------
-- Pins
----------------------------------------------------------------------------

local worldPins, worldPinsUsed = {}, 0
local minimapPins, minimapPinsUsed = {}, 0

local OpenMenu  -- defined with the menu, used by the pin handlers

local function AddItemLine(itemID, claimedNote)
    local info = ItemInfo(itemID)
    local name = info and info[1] or ("Item " .. itemID)
    local color = info and ITEM_QUALITY_COLORS[info[2]] or ITEM_QUALITY_COLORS[1]

    if claimedNote and db.claimed[itemID] then
        GameTooltip:AddDoubleLine(name, "claimed", color.r, color.g, color.b, 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine(name, color.r, color.g, color.b)
    end
end

local function PinTooltip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")

    local items = pin.items
    if pin.zoneName then
        GameTooltip:AddLine(pin.zoneName, 1, 0.82, 0)
        GameTooltip:AddLine(string.format("%d Worldforged %s here", #items,
            #items == 1 and "find" or "finds"), 1, 1, 1)
        GameTooltip:AddLine(" ")

        for i = 1, math.min(#items, TOOLTIP_ITEMS) do
            AddItemLine(items[i], true)
        end
        if #items > TOOLTIP_ITEMS then
            GameTooltip:AddLine(string.format("and %d more", #items - TOOLTIP_ITEMS), 0.6, 0.6, 0.6)
        end

    elseif #items == 1 then
        local itemID = items[1]
        local info = ItemInfo(itemID)

        AddItemLine(itemID)
        if info then
            local slot = ns.slotNames[info[4]]
            GameTooltip:AddLine(string.format("Item Level %d%s", info[3],
                slot and (" - " .. slot) or ""), 0.8, 0.8, 0.8)
        end

        if db.claimed[itemID] then
            GameTooltip:AddLine("Already claimed on this character", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("Worldforged - not yet claimed", 0.1, 1.0, 0.1)
        end

        -- The real tooltip, if the client has the item cached; the server sends
        -- it on first sight, so this fills in a moment after the first hover.
        local link = select(2, GetItemInfo(itemID))
        if link then
            GameTooltip:AddLine(" ")
            GameTooltip:SetHyperlink(link)
        end
    else
        GameTooltip:AddLine(string.format("%d Worldforged finds here", #items), 1, 0.82, 0)
        GameTooltip:AddLine(" ")

        for i = 1, math.min(#items, TOOLTIP_ITEMS) do
            AddItemLine(items[i], true)
        end

        if #items > TOOLTIP_ITEMS then
            GameTooltip:AddLine(string.format("and %d more", #items - TOOLTIP_ITEMS), 0.6, 0.6, 0.6)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click for options", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function PinClick(pin, button)
    if button == "RightButton" then
        OpenMenu(pin)
    end
end

local function AcquirePin(pool, used, parent, size)
    local pin = pool[used]
    if not pin then
        pin = CreateFrame("Button", nil, parent)
        pin:SetWidth(size)
        pin:SetHeight(size)
        pin:EnableMouse(true)
        pin:RegisterForClicks("RightButtonUp")

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

        local count = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", 2, -2)
        pin.count = count

        pin.items = {}

        -- The handlers read what they need off the frame they are called with,
        -- so they are set once here rather than re-hooked on every refresh.
        pin:SetScript("OnEnter", PinTooltip)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pin:SetScript("OnClick", PinClick)

        pool[used] = pin
    end

    pin:SetParent(parent)
    pin:SetWidth(size)
    pin:SetHeight(size)
    return pin
end

-- The pin's look is decided by the best item in it: on a cluster that is the
-- one worth walking over for, and on a single find it is simply the item.
local function DressPin(pin, items, best, zoneName)
    pin.items = items
    pin.zoneName = zoneName
    pin.icon:SetTexture(GetItemIcon(best) or FALLBACK_ICON)

    local info = ItemInfo(best)
    local color = info and ITEM_QUALITY_COLORS[info[2]]
    if color then
        pin.border:SetTexture(color.r, color.g, color.b)
    else
        pin.border:SetTexture(0, 0, 0)
    end

    if #items > 1 then
        pin.count:SetText(tostring(#items))
    else
        pin.count:SetText("")
    end

    pin:SetAlpha(db.claimed[best] and 0.4 or 1.0)
    pin:Show()
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

-- Blizzard's WorldMapButton covers the map and takes every mouse event; a pin
-- has to be its child to be hoverable at all. WorldMapDetailFrame is only the
-- fallback, and there for the same reason the Astrolabe-less path is: better a
-- pin that cannot be hovered than no pin.
local function PinParent()
    return _G["WorldMapButton"] or WorldMapDetailFrame
end

local shownHere, totalHere, pinsOnMap = 0, 0, 0

local clusterX, clusterY, clusterItems, clusterBest = {}, {}, {}, {}

-- The item a marker wears and colours itself by: the best thing under it, so a
-- rare find is never hidden behind the grey one that landed on top of it.
local function Better(a, b)
    if not a then return b end
    local ia, ib = ItemInfo(a), ItemInfo(b)
    if ia and ib and ib[2] > ia[2] then return b end
    return a
end

-- Every visible find of one zone, in the coordinates of the map now open.
-- Astrolabe answers nil for a point that cannot be shown there at all.
local function EachVisiblePoint(entry, index, continent, zone, onZoneMap, fn)
    for across, down, itemID in ZonePoints(entry) do
        if IsVisible(itemID) then
            local nx, ny = across, down
            if Astrolabe then
                nx, ny = Astrolabe:TranslateWorldMapPosition(index.c, index.z,
                    across, down, continent, zone)
            elseif not onZoneMap then
                nx = nil  -- a zone fraction means nothing on a continent
            end

            if nx and ny and nx > 0 and nx <= 1 and ny > 0 and ny <= 1 then
                fn(nx, ny, itemID)
            end
        end
    end
end

-- One pin per zone, at the middle of that zone's finds. See the note at the top
-- for why a continent does not get individual pins.
local function BuildZoneMarkers(continent, zone, place)
    for _, entry in ipairs(ns.zones) do
        local index = zoneIndex[entry.zone]
        if index and index.c == continent then
            local sumX, sumY, count, items, best, seen = 0, 0, 0, {}, nil, {}

            EachVisiblePoint(entry, index, continent, zone, false, function(nx, ny, itemID)
                sumX, sumY, count = sumX + nx, sumY + ny, count + 1
                if not seen[itemID] then
                    seen[itemID] = true
                    items[#items + 1] = itemID
                    best = Better(best, itemID)
                end
            end)

            if best then
                -- Led by quality, so the tooltip's first lines are the reason to
                -- go rather than the first row of the spawn table.
                table.sort(items, function(a, b)
                    local ia, ib = ItemInfo(a), ItemInfo(b)
                    if ia[2] ~= ib[2] then return ia[2] > ib[2] end
                    return ia[1] < ib[1]
                end)
                -- The centroid is of the spots, not of the distinct items: it
                -- should sit where the finds actually are.
                place(sumX / count, sumY / count, items, best, entry.zone)
            end
        end
    end
end

-- One pin per find, bucketed into a grid one pin wide so two spots a few yards
-- apart do not draw on top of each other.
local function BuildZoneMapMarkers(entry, index, continent, zone, cellW, cellH, place)
    for key in pairs(clusterItems) do
        clusterX[key], clusterY[key], clusterItems[key], clusterBest[key] = nil, nil, nil, nil
    end

    local order = {}

    EachVisiblePoint(entry, index, continent, zone, true, function(nx, ny, itemID)
        local key = math.floor(nx / cellW) * 4096 + math.floor(ny / cellH)
        local items = clusterItems[key]
        if not items then
            items = {}
            clusterItems[key] = items
            clusterX[key], clusterY[key] = nx, ny
            order[#order + 1] = key
        end

        -- Two spots in one cell holding the same item are one thing to collect,
        -- so the marker counts it once rather than promising a second copy.
        for i = 1, #items do
            if items[i] == itemID then return end
        end

        items[#items + 1] = itemID
        clusterBest[key] = Better(clusterBest[key], itemID)
    end)

    for i = 1, #order do
        local key = order[i]
        place(clusterX[key], clusterY[key], clusterItems[key], clusterBest[key])
    end
end

local function UpdateWorldMap()
    worldPinsUsed = 0
    shownHere, totalHere, pinsOnMap = 0, 0, 0

    if not db.enabled or not WorldMapFrame:IsShown() then
        HideFrom(worldPins, 1)
        return
    end

    local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone()
    local texture = GetMapInfo()
    local onZoneMap = (zone and zone > 0)
    local entry = onZoneMap and ZoneEntryForTexture(texture) or nil

    if entry then
        shownHere, totalHere = ZoneCounts(entry)
    end

    -- Cosmic and Azeroth (continent 0 / -1) would put every find in the world on
    -- one screen, which is not a map any more.
    if not continent or continent < 1 or (not onZoneMap and not db.continentPins)
        or (onZoneMap and not entry) then
        HideFrom(worldPins, 1)
        return
    end

    local width, height = WorldMapDetailFrame:GetWidth(), WorldMapDetailFrame:GetHeight()
    if not width or width <= 0 then return end

    local parent = PinParent()
    local level = parent:GetFrameLevel() + 5

    local function place(nx, ny, items, best, zoneName)
        worldPinsUsed = worldPinsUsed + 1

        local pin = AcquirePin(worldPins, worldPinsUsed, parent, PIN_SIZE)
        pin:SetFrameLevel(level)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", nx * width, -ny * height)
        DressPin(pin, items, best, zoneName)
    end

    if onZoneMap then
        -- Cell size in map fractions, so a cell is CLUSTER_PX wide however
        -- Mapster has scaled the map this time.
        BuildZoneMapMarkers(entry, zoneIndex[entry.zone], continent, zone,
            CLUSTER_PX / width, CLUSTER_PX / height, place)
    else
        BuildZoneMarkers(continent, zone, place)
    end

    pinsOnMap = worldPinsUsed
    HideFrom(worldPins, worldPinsUsed + 1)
end

----------------------------------------------------------------------------
-- Minimap
----------------------------------------------------------------------------

-- Astrolabe keeps placed minimap icons positioned on its own, so this only has
-- to run when the set of pins changes - a zone change, a claim, a filter - and
-- not on every frame. No clustering here: the minimap only ever shows the
-- handful of finds within a few hundred yards.
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
                    DressPin(pin, { itemID }, itemID)
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
-- The menu
----------------------------------------------------------------------------

local menuFrame

local QUALITIES = {
    { 0, "Any quality" },
    { 2, "Uncommon and better" },
    { 3, "Rare and better" },
    { 4, "Epic only" },
}

local function Toggle(key)
    return function()
        db[key] = not db[key]
        Refresh()
    end
end

local function BuildMenu(_, level)
    if level ~= 1 then return end

    local info = UIDropDownMenu_CreateInfo()
    info.isTitle, info.notCheckable = true, true
    info.text = "Worldforged"
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.notCheckable, info.disabled = true, true
    if totalHere > 0 then
        info.text = string.format("%d of %d left in this zone", shownHere, totalHere)
    elseif pinsOnMap > 0 then
        info.text = string.format("%d markers on this map", pinsOnMap)
    else
        info.text = "No finds on this map"
    end
    UIDropDownMenu_AddButton(info, level)

    local function Check(text, key)
        local entry = UIDropDownMenu_CreateInfo()
        entry.text = text
        entry.checked = db[key]
        entry.keepShownOnClick = true
        entry.func = Toggle(key)
        UIDropDownMenu_AddButton(entry, level)
    end

    Check("Show pins", "enabled")
    Check("Hide claimed finds", "hideClaimed")
    Check("Minimap pins", "minimap")
    Check("Pins on continent maps", "continentPins")

    info = UIDropDownMenu_CreateInfo()
    info.isTitle, info.notCheckable = true, true
    info.text = "Quality"
    UIDropDownMenu_AddButton(info, level)

    for _, quality in ipairs(QUALITIES) do
        local entry = UIDropDownMenu_CreateInfo()
        entry.text = quality[2]
        entry.checked = (db.minQuality == quality[1])
        entry.func = function()
            db.minQuality = quality[1]
            Refresh()
        end
        UIDropDownMenu_AddButton(entry, level)
    end

    info = UIDropDownMenu_CreateInfo()
    info.text = "Re-sync my finds"
    info.notCheckable = true
    info.func = RequestSync
    UIDropDownMenu_AddButton(info, level)
end

function OpenMenu(anchor)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "WorldforgedAtlasMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(menuFrame, BuildMenu, "MENU")
    end

    -- Refresh first so the counts in the menu describe the map as it is now.
    UpdateWorldMap()
    ToggleDropDownMenu(1, nil, menuFrame, anchor and "cursor" or "cursor", 0, 0)
end

----------------------------------------------------------------------------
-- The button in the map's header bar
----------------------------------------------------------------------------

local mapButton

local function BuildButton()
    mapButton = CreateFrame("Button", "WorldforgedAtlasButton", WorldMapFrame)
    mapButton:SetWidth(26)
    mapButton:SetHeight(26)

    -- Beside Zoom Out, where the header bar is empty, rather than over the map:
    -- a panel that hides the part of the map it sits on is a poor trade for a
    -- map addon. If the client or Mapster has moved that button, fall back to
    -- the frame's own corner.
    local zoomOut = _G["WorldMapZoomOutButton"]
    if zoomOut then
        mapButton:SetPoint("LEFT", zoomOut, "RIGHT", 8, 0)
    else
        mapButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 320, -20)
    end

    local icon = mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\Icons\\INV_Box_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    mapButton.icon = icon

    mapButton:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    mapButton:GetNormalTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
    mapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    mapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mapButton:SetScript("OnClick", function() OpenMenu() end)

    mapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Worldforged", 1, 0.82, 0)
        if totalHere > 0 then
            GameTooltip:AddLine(string.format("%d of %d left in this zone", shownHere, totalHere),
                1, 1, 1)
        elseif pinsOnMap > 0 then
            GameTooltip:AddLine(string.format("%d markers on this map", pinsOnMap), 1, 1, 1)
        end
        GameTooltip:AddLine("Click for options", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    mapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("WORLD_MAP_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")

-- WORLD_MAP_UPDATE fires repeatedly while the map is open, and a continent map
-- is several hundred points to translate and bucket. Coalesce into one rebuild
-- per frame rather than one per event.
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
            BuildButton()
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

    if input == "menu" then
        OpenMenu()
        return
    end

    if input == "off" or input == "on" then
        db.enabled = (input == "on")
    else
        db.enabled = not db.enabled
    end

    Refresh()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WorldforgedAtlas|r: pins " ..
        (db.enabled and "shown." or "hidden."))
end
