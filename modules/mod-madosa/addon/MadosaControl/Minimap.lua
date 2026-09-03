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

-- HIGH rather than the MEDIUM a minimap button conventionally uses, because the
-- things it was sliding under are on MEDIUM; not DIALOG, which is where menus
-- and popups live and where a decoration has no business being.
local BUTTON_STRATA = "HIGH"
local BUTTON_LEVEL = 100

-- Which quadrants of the minimap are round, per shape, in the order
-- bottom-right, bottom-left, top-right, top-left.
--
-- An addon that reshapes the minimap announces it through the global
-- GetMinimapShape(), which is the whole reason a button can follow a square
-- edge without knowing anything about the addon that made it square - ElvUI
-- returns 'SQUARE' or 'ROUND' from its own setting
-- (ElvUI/Core/Modules/Maps/Minimap.lua:576). The corner and side shapes are
-- what minimap addons actually declare; they cost a table, and they are the
-- difference between following an edge and floating off it.
local MINIMAP_SHAPES = {
    ROUND                     = { true,  true,  true,  true  },
    SQUARE                    = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true  },
    ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
    ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
    ["SIDE-LEFT"]             = { false, true,  false, true  },
    ["SIDE-RIGHT"]            = { true,  false, true,  false },
    ["SIDE-TOP"]              = { false, false, true,  true  },
    ["SIDE-BOTTOM"]           = { true,  true,  false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
    ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
    ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
    ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

local function MinimapShape()
    return (GetMinimapShape and GetMinimapShape()) or "ROUND"
end

-- Where on the minimap's edge a given angle lands, as an offset from its
-- centre. Measured from the minimap rather than from the constant 80 every
-- example uses: that is the ring of a stock 140px minimap, and 80px from the
-- centre of the 220px one ElvUI is configured with here is *inside* the map,
-- on its own surface, where a button draws perfectly and never sees a mouse
-- event.
local function RingOffset(angleDegrees)
    local angle = math.rad(angleDegrees)
    local x, y = math.cos(angle), math.sin(angle)

    local quadrant = 1
    if x < 0 then quadrant = quadrant + 1 end
    if y > 0 then quadrant = quadrant + 2 end

    local w = Minimap:GetWidth() / 2 + RING_MARGIN
    local h = Minimap:GetHeight() / 2 + RING_MARGIN
    if w <= RING_MARGIN or h <= RING_MARGIN then
        w, h = 80, 80   -- before the minimap has been given a size
    end

    if (MINIMAP_SHAPES[MinimapShape()] or MINIMAP_SHAPES.ROUND)[quadrant] then
        return x * w, y * h   -- a round quadrant: straight out onto the ellipse
    end

    -- A square quadrant. Push the point out along its own direction until it is
    -- past the corner, then clamp it back inside the box: the clamp is what
    -- makes the button slide along a flat side instead of cutting across it,
    -- and it is why an angle is still the right thing to store for a minimap
    -- that is not round.
    local diagonalW = math.sqrt(2 * w * w) - RING_MARGIN
    local diagonalH = math.sqrt(2 * h * h) - RING_MARGIN
    return math.max(-w, math.min(x * diagonalW, w)),
           math.max(-h, math.min(y * diagonalH, h))
end

local button

local function db()
    MadosaControlDB.minimap = MadosaControlDB.minimap or {}
    return MadosaControlDB.minimap
end

local function UpdatePosition()
    if not button then return end
    local x, y = RingOffset(db().angle or DEFAULT_ANGLE)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Setting a frame's strata takes its children with it, and ElvUI configures the
-- minimap at PLAYER_LOGIN - long after this addon has built its button at
-- ADDON_LOADED. So whatever the button was put above at build time, ElvUI's
-- Minimap:SetFrameStrata('LOW') afterwards puts it back underneath. Stating it
-- once is not enough; it has to be restated whenever the minimap's own layer
-- moves, which also covers a profile switch or a resize later in the session.
local function AssertLayer()
    if not button then return end
    button:SetFrameStrata(BUTTON_STRATA)
    button:SetFrameLevel(BUTTON_LEVEL)
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

    AssertLayer()
    UpdatePosition()
    Recolour()
    if db().hide then button:Hide() end

    -- Re-stated after anything moves the minimap, rather than trusted to hold.
    -- AssertLayer only ever touches the button, so hooking the minimap's own
    -- setters cannot recurse.
    if hooksecurefunc then
        hooksecurefunc(Minimap, "SetFrameStrata", AssertLayer)
        hooksecurefunc(Minimap, "SetFrameLevel", AssertLayer)
        -- The size matters as much as the layer: at ADDON_LOADED the minimap is
        -- still Blizzard's 140px, and the ring is measured from whatever it is
        -- when asked. ElvUI resizing it to 220 later would otherwise leave the
        -- button on the ring of a map that no longer exists.
        hooksecurefunc(Minimap, "SetWidth", UpdatePosition)
        hooksecurefunc(Minimap, "SetHeight", UpdatePosition)
    end

    -- ElvUI is finished by the time the world is up; this is the backstop for
    -- anything that changed the minimap without going through those setters.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", function()
        AssertLayer()
        UpdatePosition()
    end)
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

    local angle = db().angle or DEFAULT_ANGLE
    local x, y = RingOffset(angle)
    out:AddMessage(string.format(
        "|cff1ba6edMadosaControl|r: minimap %.0fx%.0f %s, angle %.0f -> %.0f, %.0f, button %.0fpx %s",
        Minimap:GetWidth(), Minimap:GetHeight(), MinimapShape(), angle, x, y,
        button:GetWidth(), button:IsShown() and "shown" or "hidden"))
    out:AddMessage(string.format("  button: strata %s level %d   minimap: strata %s level %d",
        button:GetFrameStrata(), button:GetFrameLevel(),
        Minimap:GetFrameStrata(), Minimap:GetFrameLevel()))

    local focus = GetMouseFocus()
    out:AddMessage("  mouse is currently over: " ..
        (focus and (focus:GetName() or "an unnamed frame") or "nothing"))
end
