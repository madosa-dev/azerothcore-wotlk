-- MadosaControl: live control panel for mod-madosa's server settings.
--
-- Talks to the mod-madosa addon bridge (mod_madosa_addon_bridge.cpp) over a
-- self-whisper addon message (SendAddonMessage(..., "WHISPER", <own name>)) -
-- the same self-whisper + LANG_ADDON trick every WotLK addon bridge uses.
-- Changes take effect on the server immediately, no restart, and persist
-- across restarts. Requires a GM account with the "Command: madosa" RBAC
-- permission (data/sql/db-auth/base/madosa_settings_rbac.sql).
--
-- The panel knows nothing about any individual setting. Protocol 2 sends each
-- one fully described - widget type, bounds, which panel it belongs on, its
-- label and its explanation - so a setting added on the server appears here,
-- correctly grouped and correctly bounded, without this file being touched.
-- The categories down the left side are simply the distinct groups the server
-- sent, in the order it sent them.

local ADDON_PREFIX = "MADOSA"
local FIELD_SEP = "~"

local PANEL_WIDTH, PANEL_HEIGHT = 840, 560
local NAV_WIDTH = 176
local ROW_HEIGHT = 30
local ROW_GAP = 4

MadosaControlDB = MadosaControlDB or {}

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

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

local settings = {}    -- key -> { value, type, min, max, group, label, help }
local order = {}       -- keys, in the order the server sent them
local groups = {}      -- group names, in first-seen order
local pending = {}     -- key -> the value the user has dialled in but not applied
local rows = {}        -- reused row frames, one per visible line
local currentGroup

local frame, navHolder, scroll, statusText, applyButton, revertButton
local navButtons = {}

local function ValueOf(key)
    if pending[key] ~= nil then return pending[key] end
    return settings[key] and settings[key].value or ""
end

local function IsDirty(key)
    local wanted = pending[key]
    local setting = settings[key]
    if wanted == nil or not setting then return false end

    if setting.type == "bool" then
        return wanted ~= setting.value
    end

    -- Numbers compared as numbers. The panel formats a float as "1.50" where
    -- the server sends "1.5", and comparing those as text would report a
    -- setting nobody touched as changed.
    return (tonumber(wanted) or 0) ~= (tonumber(setting.value) or 0)
end

local function PendingCount()
    local count = 0
    for key in pairs(pending) do
        if IsDirty(key) then count = count + 1 end
    end
    return count
end

local function SetStatus(text, kind)
    if not statusText then return end
    local color = MadosaUI.color.textDim
    if kind == "error" then color = MadosaUI.color.bad
    elseif kind == "good" then color = MadosaUI.color.good end
    statusText:SetTextColor(color[1], color[2], color[3], color[4])
    statusText:SetText(text or "")
end

local function UpdateFooter()
    local count = PendingCount()
    if count > 0 then
        applyButton.label:SetText("Apply (" .. count .. ")")
        applyButton.label:SetTextColor(MadosaUI.color.accent[1], MadosaUI.color.accent[2], MadosaUI.color.accent[3], 1)
    else
        applyButton.label:SetText("Apply")
        applyButton.label:SetTextColor(MadosaUI.color.textDim[1], MadosaUI.color.textDim[2], MadosaUI.color.textDim[3], 1)
    end
end

----------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------

-- One row per setting, built once and reused: the row keeps both controls and
-- shows whichever the setting needs, so switching categories re-labels frames
-- instead of creating new ones every time.
local function AcquireRow(index)
    if rows[index] then return rows[index] end

    local row = CreateFrame("Frame", nil, scroll.child)
    row:SetHeight(ROW_HEIGHT)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bg:SetVertexColor(1, 1, 1, 0.02)

    row:EnableMouse(true)   -- for the tooltip; children still take their own clicks

    row.label = MadosaUI.Font(row:CreateFontString(nil, "OVERLAY"), 12)
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWidth(300)

    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.dot:SetWidth(2)
    row.dot:SetPoint("TOPLEFT")
    row.dot:SetPoint("BOTTOMLEFT")
    row.dot:SetVertexColor(MadosaUI.color.accent[1], MadosaUI.color.accent[2], MadosaUI.color.accent[3], 1)
    row.dot:Hide()

    row.checkbox = MadosaUI.Checkbox(row)
    row.checkbox:SetPoint("RIGHT", -12, 0)
    row.checkbox:SetFrameLevel(row:GetFrameLevel() + 2)

    row.slider = MadosaUI.Slider(row, 260)
    row.slider:SetPoint("RIGHT", -12, 0)
    row.slider:SetFrameLevel(row:GetFrameLevel() + 2)

    row.reset = MadosaUI.Button(row, "Default", 62, 18)
    row.reset:SetPoint("RIGHT", -286, 0)
    row.reset:SetFrameLevel(row:GetFrameLevel() + 2)

    rows[index] = row
    return row
end

local function MarkDirty(row, key)
    if IsDirty(key) then
        row.dot:Show()
        row.label:SetTextColor(MadosaUI.color.accent[1], MadosaUI.color.accent[2], MadosaUI.color.accent[3], 1)
    else
        row.dot:Hide()
        row.label:SetTextColor(MadosaUI.color.text[1], MadosaUI.color.text[2], MadosaUI.color.text[3], 1)
    end
    UpdateFooter()
end

local function LayoutRows()
    for _, row in ipairs(rows) do row:Hide() end

    local index = 0
    local y = 0
    for _, key in ipairs(order) do
        local setting = settings[key]
        if setting.group == currentGroup then
            index = index + 1
            local row = AcquireRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row:Show()

            row.label:SetText(setting.label)
            MadosaUI.Tooltip(row, setting.label, setting.help ~= "" and setting.help or nil)

            row.reset:SetScript("OnClick", function()
                pending[key] = nil
                SendCommand("RESET", key)
            end)

            -- Detach both callbacks before touching either control. Rows are
            -- reused as you move between categories, so a control still holds
            -- the previous setting's value while it is being re-pointed at this
            -- one - and anything that fires in between would be recorded
            -- against whichever key was here before.
            row.checkbox.onValueChanged = nil
            row.slider.onValueChanged = nil

            if setting.type == "bool" then
                row.slider:Hide()
                row.checkbox:Show()
                row.checkbox:SetChecked(ValueOf(key) == "1")
                row.checkbox.onValueChanged = function(checked)
                    pending[key] = checked and "1" or "0"
                    MarkDirty(row, key)
                end
            else
                row.checkbox:Hide()
                row.slider:Show()
                local isFloat = setting.type == "float"
                row.slider:SetBounds(tonumber(setting.min) or 0, tonumber(setting.max) or 100, isFloat)
                row.slider:SetValue(tonumber(ValueOf(key)) or 0, true)
                row.slider.onValueChanged = function(value)
                    pending[key] = isFloat and string.format("%.2f", value) or tostring(math.floor(value + 0.5))
                    MarkDirty(row, key)
                end
            end

            MarkDirty(row, key)
            y = y + ROW_HEIGHT + ROW_GAP
        end
    end

    scroll.child:SetHeight(math.max(y, 1))
    scroll.child:SetWidth(scroll:GetWidth())
end

----------------------------------------------------------------------------
-- Categories
----------------------------------------------------------------------------

local function SelectGroup(name)
    currentGroup = name
    MadosaControlDB.group = name
    for _, button in ipairs(navButtons) do
        button:SetSelected(button.groupName == name)
    end
    LayoutRows()
end

local function RebuildNav()
    for _, button in ipairs(navButtons) do button:Hide() end

    for index, name in ipairs(groups) do
        local button = navButtons[index]
        if not button then
            button = MadosaUI.NavButton(navHolder, name, NAV_WIDTH - 16)
            button:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 26)
            button:SetScript("OnClick", function(self) SelectGroup(self.groupName) end)
            navButtons[index] = button
        end
        button.groupName = name
        button.label:SetText(name)
        button:Show()
    end

    local wanted = MadosaControlDB.group
    local found = false
    for _, name in ipairs(groups) do
        if name == wanted then found = true end
    end
    SelectGroup(found and wanted or groups[1])
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function ApplyPending()
    local sent = 0
    for key, value in pairs(pending) do
        if IsDirty(key) then
            SendCommand("SET", key .. FIELD_SEP .. value)
            sent = sent + 1
        end
    end

    pending = {}
    if sent == 0 then
        SetStatus("Nothing changed.")
    else
        SetStatus("Sent " .. sent .. " change(s).", "good")
    end
end

local function RevertPending()
    pending = {}
    LayoutRows()
    SetStatus("Reverted to the server's values.")
end

----------------------------------------------------------------------------
-- The window
----------------------------------------------------------------------------

local function BuildFrame()
    if frame then return end

    -- Named, because UISpecialFrames (what makes Escape close it) is a list of
    -- frame *names*, not of frames.
    frame = MadosaUI.Panel(UIParent, MadosaUI.color.backdrop, true, "MadosaControlFrame")
    frame:SetWidth(PANEL_WIDTH)
    frame:SetHeight(PANEL_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        MadosaControlDB.point = { point, relative, x, y }
    end)
    frame:Hide()
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    if MadosaControlDB.point then
        local point, relative, x, y = unpack(MadosaControlDB.point)
        frame:SetPoint(point, UIParent, relative, x, y)
    else
        frame:SetPoint("CENTER")
    end

    local title = MadosaUI.Font(frame:CreateFontString(nil, "OVERLAY"), 14, "OUTLINE")
    title:SetPoint("TOPLEFT", 14, -13)
    title:SetText("Madosa")

    local subtitle = MadosaUI.Font(frame:CreateFontString(nil, "OVERLAY"), 11)
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
    subtitle:SetText("live server settings")
    subtitle:SetTextColor(MadosaUI.color.textDim[1], MadosaUI.color.textDim[2], MadosaUI.color.textDim[3], 1)

    local close = MadosaUI.Button(frame, "X", 22, 20)
    close:SetPoint("TOPRIGHT", -8, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    local headRule = MadosaUI.Divider(frame)
    headRule:SetPoint("TOPLEFT", 1, -38)
    headRule:SetPoint("TOPRIGHT", -1, -38)

    navHolder = MadosaUI.Panel(frame, MadosaUI.color.panel)
    navHolder:SetPoint("TOPLEFT", 10, -48)
    navHolder:SetPoint("BOTTOMLEFT", 10, 46)
    navHolder:SetWidth(NAV_WIDTH)

    local content = MadosaUI.Panel(frame, MadosaUI.color.panel)
    content:SetPoint("TOPLEFT", navHolder, "TOPRIGHT", 10, 0)
    content:SetPoint("BOTTOMRIGHT", -10, 46)

    scroll = MadosaUI.ScrollArea(content, "MadosaControlScroll")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -18, 8)

    local footRule = MadosaUI.Divider(frame)
    footRule:SetPoint("BOTTOMLEFT", 1, 38)
    footRule:SetPoint("BOTTOMRIGHT", -1, 38)

    statusText = MadosaUI.Font(frame:CreateFontString(nil, "OVERLAY"), 11)
    statusText:SetPoint("BOTTOMLEFT", 14, 14)
    statusText:SetJustifyH("LEFT")
    statusText:SetWidth(PANEL_WIDTH - 320)

    applyButton = MadosaUI.Button(frame, "Apply", 96, 22)
    applyButton:SetPoint("BOTTOMRIGHT", -10, 10)
    applyButton:SetScript("OnClick", ApplyPending)

    revertButton = MadosaUI.Button(frame, "Revert", 80, 22)
    revertButton:SetPoint("RIGHT", applyButton, "LEFT", -6, 0)
    revertButton:SetScript("OnClick", RevertPending)

    local refreshButton = MadosaUI.Button(frame, "Refresh", 80, 22)
    refreshButton:SetPoint("RIGHT", revertButton, "LEFT", -6, 0)
    refreshButton:SetScript("OnClick", function()
        pending = {}
        SendCommand("GET")
    end)

    tinsert(UISpecialFrames, "MadosaControlFrame")
    frame:SetScript("OnShow", UpdateFooter)
end

----------------------------------------------------------------------------
-- Incoming messages
----------------------------------------------------------------------------

local function HandleMessage(message)
    local fields = split(message)
    local opcode = table.remove(fields, 1)

    if opcode == "HELLO_ACK" then
        local protocol = tonumber(fields[1]) or 1
        if protocol < 2 then
            SetStatus("Server bridge is protocol " .. protocol .. "; this panel needs 2.", "error")
        else
            SetStatus("Connected.")
        end
        SendCommand("GET")
    elseif opcode == "SETTINGS_BEGIN" then
        settings = {}
        order = {}
        groups = {}
    elseif opcode == "SETTING" then
        local key = fields[1]
        if key and key ~= "" then
            local group = fields[6]
            if not group or group == "" then group = "Other" end

            settings[key] = {
                value = fields[2] or "",
                type  = fields[3] ~= "" and fields[3] or "int",
                min   = fields[4] or "0",
                max   = fields[5] or "100",
                group = group,
                label = (fields[7] and fields[7] ~= "") and fields[7] or key,
                help  = fields[8] or "",
            }
            table.insert(order, key)

            local known = false
            for _, name in ipairs(groups) do
                if name == group then known = true end
            end
            if not known then table.insert(groups, group) end
        end
    elseif opcode == "SETTINGS_END" then
        RebuildNav()
        SetStatus(#order .. " setting(s) in " .. #groups .. " group(s).")
    elseif opcode == "SET_ACK" then
        local ok, key, valueOrError = fields[1] == "1", fields[2], fields[3]
        if ok then
            SetStatus(key .. " = " .. valueOrError, "good")
        else
            SetStatus(key .. ": " .. (valueOrError or "failed"), "error")
        end
    elseif opcode == "RESET_ACK" then
        local ok, key, err = fields[1] == "1", fields[2], fields[3]
        if ok then
            SetStatus(key .. " reset to its config default.", "good")
        else
            SetStatus(key .. ": " .. (err or "failed"), "error")
        end
    elseif opcode == "ERROR" then
        local code, errorMessage = fields[1], fields[2]
        SetStatus((code and code ~= "" and (code .. ": ") or "") .. (errorMessage or "error"), "error")
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
            MadosaControl_BuildMinimapButton()
            -- Hooked rather than called from the toggle, so the button also
            -- notices the panel's own close button and anything else that
            -- hides it.
            frame:HookScript("OnShow", MadosaControl_RefreshMinimapButton)
            frame:HookScript("OnHide", MadosaControl_RefreshMinimapButton)
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

-- Both the slash command and the minimap button open the panel, so opening it
-- is a function rather than something the slash command happens to do.
function MadosaControl_IsShown()
    return frame and frame:IsShown()
end

function MadosaControl_Toggle()
    if not frame then return end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        SetStatus("Connecting...")
        SendCommand("HELLO")
    end
end

SLASH_MADOSACONTROL1 = "/madosa"
SLASH_MADOSACONTROL2 = "/mc"
SlashCmdList["MADOSACONTROL"] = function(input)
    if string.lower(strtrim(input or "")) == "minimap" then
        local shown = MadosaControl_ToggleMinimapButton()
        DEFAULT_CHAT_FRAME:AddMessage("|cff1ba6edMadosaControl|r: minimap button " ..
            (shown and "shown." or "hidden."))
        return
    end

    MadosaControl_Toggle()
end
