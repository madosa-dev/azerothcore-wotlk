-- MadosaControl's minimap button.
--
-- Hand-rolled rather than LibDBIcon. Four of this client's addons ship that
-- library and any of them would hand it over through LibStub, but only while
-- that addon is enabled - a button that disappears because someone turned off
-- Questie is a worse bug than the sixty lines below. The addon's own note says
-- it: no libraries and no embedded media, a drop-in folder of Lua files.
--
-- So no artwork either. Blizzard's round MiniMap-TrackingBorder is the usual
-- frame for one of these, and it would be the only thing in this addon that is
-- not flat; it is a MadosaUI.Button with an "M" in it instead, which is both
-- the addon's look and, on a UI running ElvUI, what every other minimap button
-- ends up skinned into anyway.
--
-- Position is an angle on the minimap's ring, not a point: dragging it is
-- dragging it around the circle, and one number survives a UI scale change that
-- a saved x/y offset would not.

local BUTTON_SIZE = 24
local RING_MARGIN = 10        -- how far outside the minimap's edge the ring sits
local DEFAULT_ANGLE = 205     -- lower left, where the fewest addons land

-- Measured, not assumed. The usual constant for this is 80, which is the ring
-- of a stock 140px minimap - and putting a button 80px from the centre of the
-- 220px one ElvUI is configured with here lands it *inside* the map, on top of
-- the minimap's own surface, where it draws perfectly and never sees a mouse
-- event. That is what "the icon is there and I cannot click it" was.
local function RingRadius()
    local width = Minimap:GetWidth()
    if not width or width <= 0 then return 80 end
    return width / 2 + RING_MARGIN
end

local button

local function db()
    MadosaControlDB.minimap = MadosaControlDB.minimap or {}
    return MadosaControlDB.minimap
end

local function UpdatePosition()
    local angle = math.rad(db().angle or DEFAULT_ANGLE)
    local radius = RingRadius()
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        radius * math.cos(angle), radius * math.sin(angle))
end

-- The angle from the minimap's centre to the cursor. GetCursorPosition() is in
-- screen pixels and the minimap in its own scaled units, so one has to be
-- divided into the other before the two can be subtracted.
local function AngleToCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then return nil end

    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    return math.deg(math.atan2(py / scale - my, px / scale - mx))
end

local function OnDragUpdate()
    local angle = AngleToCursor()
    if angle then
        db().angle = angle
        UpdatePosition()
    end
end

local function Recolour()
    if not button then return end
    -- The accent colour is what carries a value everywhere else in this addon;
    -- here it is what says the panel is open.
    local open = MadosaControl_IsShown and MadosaControl_IsShown()
    local c = open and MadosaUI.color.accent or MadosaUI.color.text
    button.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function Build()
    -- A Button, not a MadosaUI.Panel. A Frame with EnableMouse does receive
    -- OnMouseUp, so the first version looked right and would not click: with
    -- RegisterForDrag on it, the couple of pixels a hand moves during a press
    -- is enough for the client to call it a drag, and telling that apart from a
    -- click by hand needs a timing guard that then eats real clicks. A Button
    -- has the distinction built in - the client simply does not fire OnClick
    -- when a drag happened - which is why every minimap button is one.
    button = MadosaUI.Button(Minimap, "M", BUTTON_SIZE, BUTTON_SIZE, "MadosaControlMinimapButton")
    -- ElvUI puts the minimap at strata LOW, level 10; HIGH clears that and
    -- anything else that ends up over the map without a fight.
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    MadosaUI.Font(button.label, 14, "OUTLINE")
    button.Recolour = Recolour

    -- MadosaUI.Button lights its label on hover, which is the one thing the
    -- label already means here, so the border carries the hover instead.
    button:SetScript("OnEnter", function(self)
        local a = MadosaUI.color.accent
        self:SetBackdropBorderColor(a[1], a[2], a[3], a[4])
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MadosaControl", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open the panel", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click to hide this button", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move it around the minimap", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        local b = MadosaUI.color.border
        self:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
        Recolour()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(_, click)
        if click == "RightButton" then
            db().hide = true
            button:Hide()
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff1ba6edMadosaControl|r: minimap button hidden - /madosa minimap brings it back.")
        else
            MadosaControl_Toggle()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdatePosition()
    Recolour()
    if db().hide then button:Hide() end
end

-- Called from Core.lua once MadosaControlDB has been restored.
function MadosaControl_BuildMinimapButton()
    if not button then Build() end
end

function MadosaControl_ToggleMinimapButton()
    if not button then return end

    db().hide = not db().hide
    if db().hide then
        button:Hide()
    else
        button:Show()
        UpdatePosition()
    end
    return not db().hide
end

-- The panel tells the button when it opens or closes, so the "M" can say so.
function MadosaControl_RefreshMinimapButton()
    Recolour()
end

-- /madosa minimap debug. A minimap button lives on someone else's UI, under
-- whatever else they have installed, so when one does not answer the mouse the
-- useful thing is a measurement rather than a guess - above all GetMouseFocus(),
-- which names the frame actually taking the events.
function MadosaControl_DebugMinimapButton()
    local out = DEFAULT_CHAT_FRAME
    if not button then
        out:AddMessage("|cff1ba6edMadosaControl|r: no minimap button was built.")
        return
    end

    out:AddMessage(string.format(
        "|cff1ba6edMadosaControl|r: minimap %.0fpx, ring radius %.0f, angle %.0f, button %.0fpx %s",
        Minimap:GetWidth(), RingRadius(), db().angle or DEFAULT_ANGLE, button:GetWidth(),
        button:IsShown() and "shown" or "hidden"))
    out:AddMessage(string.format("  button: strata %s level %d   minimap: strata %s level %d",
        button:GetFrameStrata(), button:GetFrameLevel(),
        Minimap:GetFrameStrata(), Minimap:GetFrameLevel()))

    local focus = GetMouseFocus()
    out:AddMessage("  mouse is currently over: " ..
        (focus and (focus:GetName() or "an unnamed frame") or "nothing"))
end
