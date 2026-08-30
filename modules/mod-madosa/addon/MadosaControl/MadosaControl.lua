-- MadosaControl: GM control panel for mod-madosa server settings.
--
-- Talks to the mod-madosa addon bridge (mod_madosa_addon_bridge.cpp) over a
-- self-whisper addon message (SendAddonMessage(..., "WHISPER", <own name>)) -
-- the same self-whisper + LANG_ADDON trick every WotLK addon bridge (like
-- HomebrewGM) uses. Changes take effect on the server immediately, no
-- restart needed, and persist across restarts. Requires a GM account with
-- the "Command: madosa" RBAC permission (see
-- data/sql/db-auth/base/madosa_settings_rbac.sql).
--
-- The panel builds itself from whatever MadosaSettings::List() sends, so a
-- setting added on the server shows up here without touching this file. The
-- only local knowledge is the display label (LABELS below) and the control
-- type, and both degrade gracefully: an unknown key gets a label derived from
-- the key itself.

local ADDON_PREFIX = "MADOSA"
local FIELD_SEP = "~"

MadosaControlDB = MadosaControlDB or {}

local function trim(value)
    return (string.gsub(value or "", "^%s*(.-)%s*$", "%1"))
end

local function split(value)
    local fields = {}
    local start = 1
    value = value or ""
    while true do
        local pos = string.find(value, FIELD_SEP, start, true)
        if not pos then
            table.insert(fields, string.sub(value, start))
            return fields
        end
        table.insert(fields, string.sub(value, start, pos - 1))
        start = pos + 1
    end
end

----------------------------------------------------------------------------
-- Comm
----------------------------------------------------------------------------

local function SendCommand(opcode, payload)
    local player = UnitName("player")
    if not player or player == "" then return end

    local message = opcode
    if payload and payload ~= "" then
        message = message .. FIELD_SEP .. payload
    end
    SendAddonMessage(ADDON_PREFIX, message, "WHISPER", player)
end

local function RequestSettings()
    SendCommand("GET")
end

----------------------------------------------------------------------------
-- Setting presentation
----------------------------------------------------------------------------

-- Nice names for the keys we know about. A key missing here still works.
local LABELS = {
    ["professionxp.enable"]         = "Profession XP enabled",
    ["professionxp.percent"]        = "Profession XP: % of level XP per attempt",
    ["professionxp.skillmultiplier"] = "Profession skill-up multiplier",
    ["autolootpet.enable"]          = "Lootbot: auto-loot while summoned",
    ["professiontools.enable"]      = "Craftbot: grant profession tools",
    ["accountcompanions.enable"]    = "Companions shared across the account",
    ["instancequestpet.enable"]     = "Questbot: hand out instance quests",
    ["passerbybuff.enable"]                     = "Passerby buffs: bots buff nearby non-group players",
    ["passerbybuff.radius"]                     = "Passerby buffs: detection radius (yards)",
    ["passerbybuff.priest.fortitude.enable"]    = "Passerby buff: Priest - Power Word: Fortitude",
    ["passerbybuff.priest.spirit.enable"]       = "Passerby buff: Priest - Divine Spirit",
    ["passerbybuff.mage.intellect.enable"]      = "Passerby buff: Mage - Arcane Intellect",
    ["passerbybuff.druid.markofthewild.enable"] = "Passerby buff: Druid - Mark of the Wild",
    ["passerbybuff.paladin.kings.enable"]       = "Passerby buff: Paladin - Blessing of Kings",
    ["passerbybuff.paladin.wisdom.enable"]      = "Passerby buff: Paladin - Blessing of Wisdom",
    ["passerbybuff.paladin.might.enable"]       = "Passerby buff: Paladin - Blessing of Might",
}

-- Control type. Deriving this from the *value* would misread a numeric setting
-- that happens to sit at 0 or 1 - professionxp.percent defaults to exactly "1".
-- The server names every toggle "<feature>.enable", so the key is the reliable
-- signal. KINDS overrides it for anything that ever breaks that convention.
local KINDS = {}

local function KindOf(key)
    if KINDS[key] then return KINDS[key] end
    if string.sub(key, -7) == ".enable" then return "bool" end
    return "number"
end

local function LabelOf(key)
    if LABELS[key] then return LABELS[key] end
    -- "somefeature.enable" -> "Somefeature enable"
    local text = string.gsub(key, "%.", " ")
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

----------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------

local frame
local body            -- parent for the generated rows
local statusText
local controls = {}   -- key -> { kind = ..., checkbox = ... } / { kind = ..., editbox = ... }
local order = {}      -- keys in the order the server sent them
local settings = {}   -- key -> current server value (string), from the last GET

local ROW_HEIGHT = 32
local CHROME_HEIGHT = 160   -- title, buttons, hint and status around the rows

local function SetStatus(text, isError)
    if not statusText then return end
    if isError then
        statusText:SetTextColor(1, 0.35, 0.35)
    else
        statusText:SetTextColor(0.7, 0.9, 1)
    end
    statusText:SetText(text or "")
end

local function CreateBackdropFrame(name, parent, width, height)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    return f
end

local function OnDragStop(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    MadosaControlDB.point = point
    MadosaControlDB.x = x
    MadosaControlDB.y = y
end

-- Rebuilds the rows for exactly the keys the server reported. Widgets cannot be
-- destroyed in WotLK, so rows for keys that disappeared are hidden and reused
-- if the same key ever comes back.
local function RebuildRows()
    for _, control in pairs(controls) do
        if control.label then control.label:Hide() end
        if control.checkbox then control.checkbox:Hide() end
        if control.editbox then control.editbox:Hide() end
    end

    local y = -8
    for _, key in ipairs(order) do
        local kind = KindOf(key)
        local control = controls[key]

        if not control or control.kind ~= kind then
            control = { kind = kind }
            control.label = body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            control.label:SetWidth(250)
            control.label:SetJustifyH("LEFT")

            if kind == "bool" then
                control.checkbox = CreateFrame("CheckButton", "MadosaControl_" .. string.gsub(key, "%.", "_"),
                                               body, "UICheckButtonTemplate")
                control.checkbox:SetWidth(24)
                control.checkbox:SetHeight(24)
            else
                control.editbox = CreateFrame("EditBox", "MadosaControl_" .. string.gsub(key, "%.", "_"),
                                              body, "InputBoxTemplate")
                control.editbox:SetAutoFocus(false)
                control.editbox:SetWidth(60)
                control.editbox:SetHeight(20)
                control.editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                control.editbox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            end
            controls[key] = control
        end

        control.label:SetText(LabelOf(key))
        control.label:ClearAllPoints()
        control.label:SetPoint("TOPLEFT", 0, y)
        control.label:Show()

        if kind == "bool" then
            control.checkbox:ClearAllPoints()
            control.checkbox:SetPoint("TOPRIGHT", -6, y + 4)
            control.checkbox:SetChecked(settings[key] == "1")
            control.checkbox:Show()
        else
            control.editbox:ClearAllPoints()
            control.editbox:SetPoint("TOPRIGHT", -12, y)
            control.editbox:SetText(settings[key] or "")
            control.editbox:Show()
        end

        y = y - ROW_HEIGHT
    end

    frame:SetHeight(CHROME_HEIGHT + math.max(1, table.getn(order)) * ROW_HEIGHT)
end

local function MadosaControl_Apply()
    local changed = 0
    for _, key in ipairs(order) do
        local control = controls[key]
        if control then
            local value

            if control.kind == "bool" then
                value = control.checkbox:GetChecked() and "1" or "0"
            else
                value = trim(control.editbox:GetText())
                if value == "" or not tonumber(value) then
                    SetStatus(LabelOf(key) .. " needs a number.", true)
                    return
                end
            end

            if value ~= settings[key] then
                SendCommand("SET", key .. FIELD_SEP .. value)
                changed = changed + 1
            end
        end
    end

    if changed == 0 then
        SetStatus("Nothing changed.")
    else
        SetStatus("Sent " .. changed .. " change(s)...")
    end
end

local function BuildFrame()
    frame = CreateBackdropFrame("MadosaControlFrame", UIParent, 400, CHROME_HEIGHT + 4 * ROW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", OnDragStop)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    if MadosaControlDB.point then
        frame:ClearAllPoints()
        frame:SetPoint(MadosaControlDB.point, UIParent, MadosaControlDB.point, MadosaControlDB.x, MadosaControlDB.y)
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("mod-madosa control")

    local closeButton = CreateFrame("Button", "MadosaControlFrameCloseButton", frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    body = CreateFrame("Frame", "MadosaControlBody", frame)
    body:SetPoint("TOPLEFT", 24, -50)
    body:SetPoint("BOTTOMRIGHT", -24, 78)

    local applyButton = CreateFrame("Button", "MadosaControlApplyButton", frame, "UIPanelButtonTemplate")
    applyButton:SetWidth(90)
    applyButton:SetHeight(22)
    applyButton:SetPoint("BOTTOMLEFT", 20, 46)
    applyButton:SetText("Apply")
    applyButton:SetScript("OnClick", MadosaControl_Apply)

    local refreshButton = CreateFrame("Button", "MadosaControlRefreshButton", frame, "UIPanelButtonTemplate")
    refreshButton:SetWidth(90)
    refreshButton:SetHeight(22)
    refreshButton:SetPoint("LEFT", applyButton, "RIGHT", 8, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        SetStatus("Refreshing...")
        RequestSettings()
    end)

    local resetHint = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    resetHint:SetPoint("BOTTOMLEFT", 20, 28)
    resetHint:SetPoint("RIGHT", -20, 0)
    resetHint:SetJustifyH("LEFT")
    resetHint:SetText('Use ".madosa reset <key>" in chat to revert a setting to the server config default.')
    resetHint:SetTextColor(0.6, 0.6, 0.6)

    statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOMLEFT", 20, 12)
    statusText:SetPoint("RIGHT", -20, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")

    tinsert(UISpecialFrames, "MadosaControlFrame")
end

----------------------------------------------------------------------------
-- Incoming messages
----------------------------------------------------------------------------

local function HandleMessage(message)
    local fields = split(message)
    local opcode = table.remove(fields, 1)

    if opcode == "HELLO_ACK" then
        SetStatus("Connected (protocol " .. (fields[1] or "?") .. ").")
        RequestSettings()
    elseif opcode == "SETTINGS_BEGIN" then
        order = {}
        settings = {}
    elseif opcode == "SETTING" then
        local key, value = fields[1], fields[2]
        if key and key ~= "" then
            if settings[key] == nil then
                table.insert(order, key)
            end
            settings[key] = value
        end
    elseif opcode == "SETTINGS_END" then
        RebuildRows()
        SetStatus("Loaded " .. table.getn(order) .. " setting(s) from the server.")
    elseif opcode == "SET_ACK" then
        local ok, key, valueOrError = fields[1] == "1", fields[2], fields[3]
        SetStatus(ok and (key .. " = " .. valueOrError) or (key .. ": " .. (valueOrError or "failed")), not ok)
    elseif opcode == "RESET_ACK" then
        local ok, key, err = fields[1] == "1", fields[2], fields[3]
        SetStatus(ok and (key .. " reset to config default.") or (key .. ": " .. (err or "failed")), not ok)
    elseif opcode == "ERROR" then
        local code, errorMessage = fields[1], fields[2]
        SetStatus((code and code ~= "" and (code .. ": ") or "") .. (errorMessage or "error"), true)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "MadosaControl" then
            BuildFrame()
        end
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

SLASH_MADOSACONTROL1 = "/madosa"
SLASH_MADOSACONTROL2 = "/mc"
SlashCmdList["MADOSACONTROL"] = function()
    if not frame then return end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        SetStatus("Connecting...")
        SendCommand("HELLO")
    end
end
