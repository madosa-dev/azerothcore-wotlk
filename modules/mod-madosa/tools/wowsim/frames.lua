-- The frames and map API the client itself puts up before any addon runs.
--
-- An addon may reasonably assume Minimap, WorldMapFrame and the chat frames
-- exist; pfQuest reads Minimap:GetChildren() on its second file. These are the
-- few pieces of FrameXML that are not optional, built here so an addon finds
-- them where it expects. Their state comes out of World, so a scenario can put
-- the player somewhere and zoom the minimap.

World.zone = World.zone or "Elwynn Forest"
World.subzone = World.subzone or ""
World.mapPosition = World.mapPosition or { 0.5, 0.5 }
World.minimapZoom = World.minimapZoom or 3
World.cvars = World.cvars or { minimapZoom = "3", minimapInsideZoom = "2", rotateMinimap = "0" }

Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetWidth(140)
Minimap:SetHeight(140)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
function Minimap:GetZoom() return World.minimapZoom end
function Minimap:SetZoom(z) World.minimapZoom = math.max(0, math.min(5, z or 0)) end
function Minimap:PingLocation() end
function Minimap:SetMaskTexture() end
function Minimap:SetBlipTexture() end

-- The client's own minimap children. pfQuest walks them looking for the
-- rotating player arrow, by model path, so one carries that model.
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MiniMapCompassRing = CreateFrame("Model", "MiniMapCompassRing", Minimap)
function MiniMapCompassRing:GetFacing() return World.facing or 0 end
function MiniMapCompassRing:SetFacing(f) World.facing = f end

for i = 1, 8 do
    local child = CreateFrame("Model", "MinimapChild" .. i, Minimap)
    child._model = i == 9 and "" or ""
    function child:GetModel() return self._model or "" end
    function child:GetFacing() return World.facing or 0 end
    function child:SetFacing(f) World.facing = f end
end
MinimapPlayerArrow = CreateFrame("Model", "MinimapPlayerArrow", Minimap)
MinimapPlayerArrow._model = "interface\\minimap\\minimaparrow"
function MinimapPlayerArrow:GetModel() return self._model end
function MinimapPlayerArrow:GetFacing() return World.facing or 0 end
function MinimapPlayerArrow:SetFacing(f) World.facing = f end

MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", MinimapCluster)
MinimapZoneText = MinimapCluster:CreateFontString("MinimapZoneText", "OVERLAY", "GameFontNormalSmall")
MinimapZoneTextButton = CreateFrame("Button", "MinimapZoneTextButton", MinimapCluster)
MiniMapTracking = CreateFrame("Frame", "MiniMapTracking", MinimapCluster)

WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:SetWidth(1024)
WorldMapFrame:SetHeight(768)
WorldMapFrame:Hide()
WorldMapDetailFrame = CreateFrame("Frame", "WorldMapDetailFrame", WorldMapFrame)
WorldMapDetailFrame:SetWidth(1002)
WorldMapDetailFrame:SetHeight(668)
WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 11, -11)
WorldMapButton = CreateFrame("Button", "WorldMapButton", WorldMapDetailFrame)
WorldMapButton:SetAllPoints(WorldMapDetailFrame)
WorldMapBlobFrame = CreateFrame("Frame", "WorldMapBlobFrame", WorldMapFrame)
WorldMapPositioningGuide = CreateFrame("Frame", "WorldMapPositioningGuide", WorldMapFrame)
WorldMapQuestFrame = CreateFrame("Frame", "WorldMapQuestFrame", WorldMapFrame)
QuestLogFrame = CreateFrame("Frame", "QuestLogFrame", UIParent)
QuestLogFrame:Hide()
GameTooltip = GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)

for i = 1, 7 do
    local chat = CreateFrame("Frame", "ChatFrame" .. i, UIParent)
    chat.AddMessage = function(_, msg) CHAT[#CHAT + 1] = tostring(msg) end
end
DEFAULT_CHAT_FRAME = ChatFrame1

-- Where the player is, and on which map ----------------------------------

function GetRealZoneText() return World.zone end
function GetZoneText() return World.zone end
function GetSubZoneText() return World.subzone end
function GetMinimapZoneText() return World.subzone ~= "" and World.subzone or World.zone end
function GetPlayerMapPosition(unit)
    if unit ~= "player" then return 0, 0 end
    return World.mapPosition[1], World.mapPosition[2]
end
function SetMapToCurrentZone() World.mapSetToZone = true end
function SetMapZoom() end
function GetCurrentMapAreaID() return World.mapAreaID or 0 end
function GetCurrentMapZone() return World.mapZone or 0 end
function GetCurrentMapContinent() return World.mapContinent or 0 end
function GetMapInfo() return World.mapFile or "Elwynn" end
function GetMapContinents() return "Eastern Kingdoms", "Kalimdor", "Outland", "Northrend" end
function GetMapZones() return end
function WorldMapFrame_ClearQuestPOIs() end
function GetNumMapLandmarks() return 0 end
function ToggleDropDownMenu() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_AddButton() end
function CloseDropDownMenus() end

-- FrameXML tables and calls an addon may reach for --------------------------

StaticPopupDialogs = {}
UIPanelWindows = {}
UISpecialFrames = {}
UIMenus = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end
function GameTooltip_SetDefaultAnchor() end
function ShowUIPanel() end
function HideUIPanel() end

-- The quest log. Entries come from World.questLog, a list of
-- { title, level, tag, isHeader, complete, objectives = { {text, type, done, needed}, ... } }
World.questLog = World.questLog or {}
World.questSelection = World.questSelection or 1

function GetNumQuestLogEntries()
    local quests = 0
    for _, entry in ipairs(World.questLog) do
        if not entry.isHeader then quests = quests + 1 end
    end
    return #World.questLog, quests
end
function GetQuestLogTitle(index)
    local q = World.questLog[index]
    if not q then return nil end
    return q.title, q.level or 1, q.tag, q.group, q.isHeader, q.collapsed,
        q.complete, q.daily, q.id
end
function SelectQuestLogEntry(index) World.questSelection = index end
function GetQuestLogSelection() return World.questSelection end
function GetQuestLogQuestText()
    local q = World.questLog[World.questSelection]
    return q and q.description or "", q and q.objectivesText or ""
end
function GetNumQuestLeaderBoards(index)
    local q = World.questLog[index or World.questSelection]
    return q and q.objectives and #q.objectives or 0
end
function GetQuestLogLeaderBoard(i, index)
    local q = World.questLog[index or World.questSelection]
    local o = q and q.objectives and q.objectives[i]
    if not o then return nil end
    return o.text, o.type or "monster", o.done or false
end
function ExpandQuestHeader() end
function CollapseQuestHeader() end
function IsQuestWatched() return false end
function AddQuestWatch() end
function RemoveQuestWatch() end
function GetQuestLogRewardInfo() return nil end
function GetNumQuestLogRewards() return 0 end
function GetNumQuestLogChoices() return 0 end
function QuestLog_Update() end

function GetNumSkillLines() return 0 end
function GetSkillLineInfo() return nil end
function GetTrackingTexture() return nil end
function GetNumTrackingTypes() return 0 end
function GetProfessions() return end

-- Constants FrameXML defines that addons read straight out of the globals.

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 }, MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}
for class, colour in pairs(RAID_CLASS_COLORS) do
    colour.colorStr = string.format("ff%02x%02x%02x", colour.r * 255, colour.g * 255, colour.b * 255)
end
CLASS_BUTTONS = {}
ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "|cff1eff00" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "|cffff8000" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "|cffe6cc80" },
    [7] = { r = 0.90, g = 0.80, b = 0.50, hex = "|cffe6cc80" },
}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
MAX_PLAYER_LEVEL = 80
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
RED_FONT_COLOR = { r = 1, g = 0.1, b = 0.1 }
GREEN_FONT_COLOR = { r = 0.1, g = 1, b = 0.1 }
