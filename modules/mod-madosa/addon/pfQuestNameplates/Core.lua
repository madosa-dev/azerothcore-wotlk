-- pfQuestNameplates: a quest objective icon over the nameplate of every mob
-- that is one, after the way Ascension marks them - a mob icon on something to
-- kill, a bag on something to loot.
--
-- Questie ships this (Modules/QuestieNameplate.lua) and pfQuest does not, so
-- this is the piece that goes missing when you move from one to the other.
--
-- Where "kill" and "loot" come from
-- ---------------------------------
-- Not from the quest log. Its text answers what is left ("Kobold Vermin slain:
-- 3/8") but not which mob drops the item an objective asks for, and that is
-- exactly the case a bag icon is for. pfQuest already knows: it resolves every
-- objective into map nodes tagged with a QTYPE, and the tag says which kind of
-- objective produced the node. So this reads pfQuest's answer instead of
-- computing a second, disagreeing one.
--
--     UNIT_OBJECTIVE           kill this mob                     -> mob icon
--     UNIT_OBJECTIVE_ITEMREQ   kill it for an item it carries    -> bag icon
--     ITEM_OBJECTIVE_LOOT      an objective item drops from it   -> bag icon
--     ITEM_OBJECTIVE_USE       an objective item comes from it   -> bag icon
--
-- OBJECT_*, ZONE_ and AREATRIGGER_ objectives are skipped: chests, herbs and
-- travel points have no nameplate to put anything over.
--
-- Read, not recorded
-- ------------------
-- The index is rebuilt from pfMap.nodes each time pfQuest changes them, rather
-- than accumulated by watching AddNode. pfQuest drops a finished quest with
-- DeleteNode("PFQUEST", <quest title>), one quest at a time, and a table filled
-- by watching AddNode has no way to act on that - it would keep marking mobs
-- for quests that are already handed in. Deriving the whole index from the
-- nodes that currently exist cannot go stale that way. The hooks on AddNode and
-- DeleteNode therefore only raise a flag; the rebuild happens once on the next
-- frame, however many nodes were touched.
--
-- Two kinds of nameplate
-- ----------------------
-- With ElvUI's nameplate module on - the default, and what is running here -
-- ElvUI hides Blizzard's plate and draws its own, so its frames are what the
-- icon has to attach to. It has already done the hard part: NP.VisiblePlates is
-- the set of plates on screen and each carries the mob's name in .UnitName.
--
-- Without it, there is no nameplate API on 3.3.5 at all: plates are anonymous
-- children of WorldFrame that have to be recognised by the one texture they all
-- share, and the name read out of a fixed region slot. That is the fallback
-- below, and it uses the same recognition ElvUI itself does, so the two agree
-- about what a nameplate is.

local ADDON_PATH = "Interface\\AddOns\\pfQuestNameplates\\"

-- pfQuest's own cluster art, so a nameplate icon is the same picture as the
-- marker for that objective on the map.
local ART = {
    slay = "img\\cluster_mob",
    loot = "img\\cluster_item",
}

-- Blizzard's plate border, the one texture every default nameplate has and
-- nothing else does. ElvUI recognises plates by exactly this.
local PLATE_OVERLAY = "Interface\\Tooltips\\Nameplate-Border"

-- The node tags worth an icon, and which icon.
local KIND = {
    UNIT_OBJECTIVE = "slay",
    UNIT_OBJECTIVE_ITEMREQ = "loot",
    ITEM_OBJECTIVE_LOOT = "loot",
    ITEM_OBJECTIVE_USE = "loot",
}

-- How often the plates on screen are re-checked. A plate changes what it shows
-- only when the mob under it changes, so this is about how fast a new plate
-- gets its icon, not about smoothness.
local UPDATE_INTERVAL = 0.15

pfQuestNameplatesDB = pfQuestNameplatesDB or {}

local defaults = {
    enabled = true,
    size = 18,
    -- Off the left edge, clear of ElvUI's health bar and of the level text on
    -- Blizzard's plate.
    x = -6,
    y = 0,
    -- Follow pfQuest's own monochrome cluster setting unless told otherwise.
    mono = nil,
}

local db

local function ApplyDefaults()
    for key, value in pairs(defaults) do
        if pfQuestNameplatesDB[key] == nil then
            pfQuestNameplatesDB[key] = value
        end
    end
    db = pfQuestNameplatesDB
end

----------------------------------------------------------------------------
-- The objective index
----------------------------------------------------------------------------

-- mob name -> "slay" | "loot"
local objectives = {}
local dirty = true

local function Texture(kind)
    local mono = db.mono
    if mono == nil then
        mono = (pfQuest_config and pfQuest_config["clustermono"] == "1")
    end
    return (pfQuestConfig and pfQuestConfig.path or ADDON_PATH) .. "\\" ..
        ART[kind] .. (mono and "_mono" or "")
end

local function Rebuild()
    for name in pairs(objectives) do objectives[name] = nil end

    local nodes = pfMap and pfMap.nodes and pfMap.nodes["PFQUEST"]
    if not nodes then return end

    -- pfQuest labels a node's spawn kind with the same localised string it uses
    -- everywhere else, so comparing against it needs no locale table of our own.
    local unitType = pfQuest_Loc and pfQuest_Loc["Unit"]

    for _, byCoords in pairs(nodes) do
        for _, byTitle in pairs(byCoords) do
            for _, node in pairs(byTitle) do
                local kind = KIND[node.QTYPE]
                if kind and node.spawn and node.spawntype == unitType then
                    -- A mob can be both: killed for one quest, looted for
                    -- another. The bag wins, because it is the instruction that
                    -- is easy to forget - you were going to kill it either way.
                    if kind == "loot" or not objectives[node.spawn] then
                        objectives[node.spawn] = kind
                    end
                end
            end
        end
    end
end

local hooked = false

local function InstallHooks()
    if hooked or not pfMap then return end
    hooked = true

    local addNode = pfMap.AddNode
    pfMap.AddNode = function(self, ...)
        dirty = true
        return addNode(self, ...)
    end

    local deleteNode = pfMap.DeleteNode
    pfMap.DeleteNode = function(self, ...)
        dirty = true
        return deleteNode(self, ...)
    end
end

----------------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------------

local icons = {}

local function IconFor(plate)
    local icon = icons[plate]
    if not icon then
        -- A frame rather than a bare texture, so it can sit above whatever the
        -- plate draws without inheriting the plate's own draw layers.
        icon = CreateFrame("Frame", nil, plate)
        icon:SetFrameLevel(plate:GetFrameLevel() + 4)
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetAllPoints(icon)
        icons[plate] = icon
    end
    return icon
end

local function ShowIcon(plate, kind)
    local icon = IconFor(plate)

    if icon.kind ~= kind then
        icon.kind = kind
        icon.texture:SetTexture(Texture(kind))
    end

    icon:SetWidth(db.size)
    icon:SetHeight(db.size)
    icon:ClearAllPoints()
    icon:SetPoint("RIGHT", plate, "LEFT", db.x, db.y)
    icon:Show()
end

local function HideIcon(plate)
    local icon = icons[plate]
    if icon then icon:Hide() end
end

local function Mark(plate, name)
    local kind = name and name ~= "" and objectives[name]
    if kind then
        ShowIcon(plate, kind)
    else
        HideIcon(plate)
    end
end

----------------------------------------------------------------------------
-- Finding the plates
----------------------------------------------------------------------------

local function ElvUINameplates()
    if not ElvUI then return nil end
    local E = ElvUI[1]
    if not E or not E.private or not E.private.nameplates
        or not E.private.nameplates.enable then
        return nil
    end
    -- The second argument keeps GetModule from erroring when the module was
    -- never loaded, which is what happens on an ElvUI build without it.
    local NP = E.GetModule and E:GetModule("NamePlates", true)
    if NP and NP.VisiblePlates then return NP end
    return nil
end

-- Blizzard plates, for when ElvUI's module is off. Children of WorldFrame are
-- only scanned when their number changes: plates are created once and reused,
-- so a new one always shows up as a new child.
local blizzPlates = {}
local lastChildCount = 0

local function ScanWorldFrame()
    local count = WorldFrame:GetNumChildren()
    if count == lastChildCount then return end

    local children = { WorldFrame:GetChildren() }
    for i = lastChildCount + 1, count do
        local frame = children[i]
        if frame and not blizzPlates[frame] then
            local overlay = frame:GetRegions()
            if overlay and overlay.IsObjectType and overlay:IsObjectType("Texture")
                and overlay:GetTexture() == PLATE_OVERLAY then
                -- Region order on a 3.3.5 plate: threat, border, castbar border,
                -- castbar shield, castbar icon, highlight, name, level, ...
                local _, _, _, _, _, _, name = frame:GetRegions()
                if name then blizzPlates[frame] = name end
            end
        end
    end

    lastChildCount = count
end

local function UpdatePlates()
    local NP = ElvUINameplates()

    if NP then
        for plate in pairs(NP.VisiblePlates) do
            if plate.IsShown and plate:IsShown() then
                Mark(plate, plate.UnitName)
            else
                HideIcon(plate)
            end
        end
        return
    end

    ScanWorldFrame()
    for plate, nameRegion in pairs(blizzPlates) do
        if plate:IsShown() then
            Mark(plate, nameRegion:GetText())
        else
            HideIcon(plate)
        end
    end
end

local function HideAll()
    for _, icon in pairs(icons) do icon:Hide() end
end

----------------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------------

local elapsed = 0
local frame = CreateFrame("Frame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "pfQuestNameplates" then
        ApplyDefaults()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyDefaults()
        InstallHooks()
        dirty = true
    end
end)

frame:SetScript("OnUpdate", function(_, delta)
    if not db then return end

    if not db.enabled then
        HideAll()
        return
    end

    -- Hooks may not be in place if pfQuest loaded after this did.
    if not hooked then InstallHooks() end

    -- One rebuild for however many nodes changed since the last frame.
    if dirty then
        dirty = false
        Rebuild()
    end

    elapsed = elapsed + (delta or 0)
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    UpdatePlates()
end)

----------------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------------

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest Nameplates|r: " .. message)
end

SLASH_PFQUESTNAMEPLATES1 = "/pfnp"
SlashCmdList["PFQUESTNAMEPLATES"] = function(input)
    local command, value = string.match(strtrim(input or ""), "^(%a*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "size" and tonumber(value) then
        db.size = math.max(6, math.min(64, tonumber(value)))
        Print("icon size " .. db.size .. ".")

    elseif command == "x" and tonumber(value) then
        db.x = tonumber(value)
        Print("icon x offset " .. db.x .. ".")

    elseif command == "y" and tonumber(value) then
        db.y = tonumber(value)
        Print("icon y offset " .. db.y .. ".")

    elseif command == "mono" then
        db.mono = not db.mono
        for _, icon in pairs(icons) do icon.kind = nil end
        Print("monochrome icons " .. (db.mono and "on." or "off."))

    elseif command == "status" then
        local count = 0
        for _ in pairs(objectives) do count = count + 1 end
        Print((db.enabled and "on" or "off") ..
            ", " .. count .. " mobs are quest objectives right now, using " ..
            (ElvUINameplates() and "ElvUI" or "Blizzard") .. " nameplates.")

    elseif command == "" or command == "on" or command == "off" then
        if command == "" then
            db.enabled = not db.enabled
        else
            db.enabled = (command == "on")
        end
        if not db.enabled then HideAll() end
        Print(db.enabled and "icons shown." or "icons hidden.")

    else
        Print("/pfnp - toggle | on | off | size <n> | x <n> | y <n> | mono | status")
    end
end
