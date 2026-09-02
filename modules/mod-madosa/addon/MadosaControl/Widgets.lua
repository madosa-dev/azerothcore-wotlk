-- MadosaControl widgets: the small set of flat, dark controls the panel is
-- built out of.
--
-- The look is ElvUI's, without ElvUI: a near-black panel, a one-pixel solid
-- border and a one-pixel shadow frame sitting behind it, one accent colour for
-- anything that carries a value, and everything else greyscale. That is the
-- whole trick - ElvUI is this one primitive repeated at every scale, which is
-- why it reads as a designed interface rather than as Blizzard frames with
-- things stacked on them.
--
-- No libraries and no embedded media: WHITE8X8 is a texture the 3.3.5a client
-- already ships, so the addon stays a drop-in folder of Lua files.

MadosaUI = {}

local WHITE = "Interface\\Buttons\\WHITE8X8"

MadosaUI.color = {
    backdrop  = { 0.05, 0.05, 0.06, 0.94 },  -- the window itself
    panel     = { 0.09, 0.09, 0.10, 1 },     -- a raised area inside it
    row       = { 0.11, 0.11, 0.12, 1 },     -- a control's own well
    border    = { 0, 0, 0, 1 },
    accent    = { 0.11, 0.65, 0.93, 1 },     -- anything carrying a value
    accentDim = { 0.11, 0.65, 0.93, 0.25 },
    text      = { 0.85, 0.85, 0.87, 1 },
    textDim   = { 0.55, 0.55, 0.58, 1 },
    good      = { 0.45, 0.85, 0.45, 1 },
    bad       = { 0.95, 0.35, 0.35, 1 },
}

local function unpack4(c)
    return c[1], c[2], c[3], c[4]
end

-- Fonts: the client's own, at a size the panel can fit a lot of, outlined so
-- 12px stays readable over a dark ground. Shipping a font file would look
-- closer to ElvUI and would cost this addon its "two files, no media" shape.
function MadosaUI.Font(fontString, size, flags)
    fontString:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    fontString:SetTextColor(unpack4(MadosaUI.color.text))
    return fontString
end

-- A flat panel with a hard 1px border, and a second frame one pixel out behind
-- it standing in for a shadow. Everything visible in this addon is one of
-- these.
function MadosaUI.Panel(parent, color, shadow, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(unpack4(color or MadosaUI.color.panel))
    frame:SetBackdropBorderColor(unpack4(MadosaUI.color.border))

    if shadow then
        -- A child of the frame, not a sibling of it. A sibling keeps standing
        -- there when the frame is hidden - which is what a window nobody has
        -- opened yet leaving a rectangle on the screen looks like. A child with
        -- a lower frame level still draws behind its parent, and hides with it
        -- for free.
        local behind = CreateFrame("Frame", nil, frame)
        behind:SetPoint("TOPLEFT", -3, 3)
        behind:SetPoint("BOTTOMRIGHT", 3, -3)
        local level = frame:GetFrameLevel() - 1
        behind:SetFrameLevel(level > 0 and level or 0)
        behind:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
        behind:SetBackdropBorderColor(0, 0, 0, 0.5)
        frame.shadow = behind
    end

    return frame
end

-- A one-pixel rule, for separating a header from what it heads.
function MadosaUI.Divider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetHeight(1)
    line:SetVertexColor(1, 1, 1, 0.07)
    return line
end

function MadosaUI.Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width or 90)
    button:SetHeight(height or 22)
    button:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    button:SetBackdropColor(unpack4(MadosaUI.color.row))
    button:SetBackdropBorderColor(unpack4(MadosaUI.color.border))

    button.label = MadosaUI.Font(button:CreateFontString(nil, "OVERLAY"), 12)
    button.label:SetPoint("CENTER")
    button.label:SetText(text)

    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack4(MadosaUI.color.accent))
        self.label:SetTextColor(unpack4(MadosaUI.color.accent))
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack4(MadosaUI.color.border))
        self.label:SetTextColor(unpack4(MadosaUI.color.text))
    end)

    return button
end

-- A navigation entry: full-width, flat, and marked by a bar down its left edge
-- rather than by a different background, so the list stays quiet until you look
-- at which one is lit.
function MadosaUI.NavButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(24)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture(WHITE)
    button.bg:SetVertexColor(1, 1, 1, 0)

    button.mark = button:CreateTexture(nil, "ARTWORK")
    button.mark:SetTexture(WHITE)
    button.mark:SetWidth(2)
    button.mark:SetPoint("TOPLEFT")
    button.mark:SetPoint("BOTTOMLEFT")
    button.mark:SetVertexColor(unpack4(MadosaUI.color.accent))
    button.mark:Hide()

    button.label = MadosaUI.Font(button:CreateFontString(nil, "OVERLAY"), 12)
    button.label:SetPoint("LEFT", 12, 0)
    button.label:SetText(text)
    button.label:SetTextColor(unpack4(MadosaUI.color.textDim))

    function button:SetSelected(selected)
        self.selected = selected
        if selected then
            self.mark:Show()
            self.bg:SetVertexColor(1, 1, 1, 0.05)
            self.label:SetTextColor(unpack4(MadosaUI.color.text))
        else
            self.mark:Hide()
            self.bg:SetVertexColor(1, 1, 1, 0)
            self.label:SetTextColor(unpack4(MadosaUI.color.textDim))
        end
    end

    button:SetScript("OnEnter", function(self)
        if not self.selected then self.bg:SetVertexColor(1, 1, 1, 0.04) end
    end)
    button:SetScript("OnLeave", function(self)
        if not self.selected then self.bg:SetVertexColor(1, 1, 1, 0) end
    end)

    button:SetSelected(false)
    return button
end

-- A checkbox with no artwork at all: an empty well that fills with the accent
-- colour when it is on.
function MadosaUI.Checkbox(parent)
    local box = CreateFrame("Button", nil, parent)
    box:SetWidth(18)
    box:SetHeight(18)
    box:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(unpack4(MadosaUI.color.row))
    box:SetBackdropBorderColor(unpack4(MadosaUI.color.border))

    box.fill = box:CreateTexture(nil, "ARTWORK")
    box.fill:SetTexture(WHITE)
    box.fill:SetPoint("TOPLEFT", 4, -4)
    box.fill:SetPoint("BOTTOMRIGHT", -4, 4)
    box.fill:SetVertexColor(unpack4(MadosaUI.color.accent))
    box.fill:Hide()

    function box:SetChecked(checked)
        self.checked = checked and true or false
        if self.checked then self.fill:Show() else self.fill:Hide() end
    end

    function box:GetChecked()
        return self.checked
    end

    box:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onValueChanged then self.onValueChanged(self.checked) end
    end)
    box:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack4(MadosaUI.color.accent)) end)
    box:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack4(MadosaUI.color.border)) end)

    box:SetChecked(false)
    return box
end

-- A slider plus the number it is showing, editable. Bounded settings get this;
-- the number is there because dragging to exactly 20 is a game of its own.
function MadosaUI.Slider(parent, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetWidth(width)
    holder:SetHeight(18)

    local track = MadosaUI.Panel(holder, MadosaUI.color.row)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT", -62, 0)
    track:SetHeight(8)

    local slider = CreateFrame("Slider", nil, track)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:SetThumbTexture(WHITE)
    local thumb = slider:GetThumbTexture()
    thumb:SetWidth(8)
    thumb:SetHeight(14)
    thumb:SetVertexColor(unpack4(MadosaUI.color.accent))

    local box = MadosaUI.Panel(holder, MadosaUI.color.row)
    box:SetPoint("RIGHT")
    box:SetWidth(56)
    box:SetHeight(18)

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetAllPoints()
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    MadosaUI.Font(edit, 11)

    holder.slider = slider
    holder.edit = edit

    -- One value, two ways in. Both funnel through here so the pair can never
    -- disagree, and `silent` keeps the slider's own OnValueChanged from
    -- bouncing back into the edit box mid-typing.
    function holder:SetValue(value, silent)
        self.value = value
        self.silent = true
        slider:SetValue(value)
        self.silent = nil
        if not edit:HasFocus() then
            edit:SetText(self.isFloat and string.format("%.2f", value) or tostring(math.floor(value + 0.5)))
        end
        if not silent and self.onValueChanged then self.onValueChanged(value) end
    end

    -- Silenced, and not as a precaution: SetMinMaxValues fires the slider's
    -- OnValueChanged whenever the value it still holds falls outside the new
    -- bounds. Re-pointing a reused row at a different setting does exactly
    -- that, and without this the clamp would be reported as the user having
    -- changed something.
    function holder:SetBounds(min, max, isFloat)
        self.isFloat = isFloat
        self.silent = true
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(isFloat and 0.1 or 1)
        self.silent = nil
        self.min, self.max = min, max
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if holder.silent then return end
        holder:SetValue(holder.isFloat and value or math.floor(value + 0.5))
    end)

    local function commit()
        local value = tonumber(edit:GetText())
        if value then
            if value < holder.min then value = holder.min end
            if value > holder.max then value = holder.max end
            holder:SetValue(value)
        else
            holder:SetValue(holder.value)
        end
        edit:ClearFocus()
    end

    edit:SetScript("OnEnterPressed", commit)
    edit:SetScript("OnEditFocusLost", commit)
    edit:SetScript("OnEscapePressed", function(self)
        holder:SetValue(holder.value)
        self:ClearFocus()
    end)

    return holder
end

-- A scroll area with the client's own scroll frame doing the work, stripped of
-- its artwork: every texture on the bar is cleared, then the thumb alone is
-- given back as a flat accent bar. Rebuilding scrolling by hand would be more
-- code and worse mouse-wheel behaviour.
function MadosaUI.ScrollArea(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local bar = _G[name .. "ScrollBar"]

    _G[bar:GetName() .. "ScrollUpButton"]:Hide()
    _G[bar:GetName() .. "ScrollDownButton"]:Hide()

    for _, region in ipairs({ bar:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:SetTexture(nil) end
    end

    local thumb = bar:GetThumbTexture()
    thumb:SetTexture(WHITE)
    thumb:SetWidth(4)
    thumb:SetVertexColor(unpack4(MadosaUI.color.accentDim))

    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 12, 0)
    bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 12, 0)
    bar:SetWidth(4)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll.child = child

    return scroll
end

function MadosaUI.Tooltip(owner, title, text)
    if not text or text == "" then return end
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(text, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
