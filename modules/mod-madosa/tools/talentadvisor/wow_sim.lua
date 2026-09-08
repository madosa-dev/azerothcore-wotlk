-- A headless stand-in for the parts of the WoW 3.3.5 client TalentAdvisor
-- touches, enough to drive the addon end to end without a game running.
--
-- wow_stub.lua next to this is the cheap version: inert frames, for the tests
-- that only exercise the pure functions. This one is the opposite - frames
-- remember their points, text, size and scripts, tooltips have readable lines,
-- and the talent, bag and equipment APIs answer out of a World table the test
-- sets up. That makes the parts that only exist inside the client testable:
-- the picker, the event flow, what the frame ends up saying, the tooltip
-- fallback, and whether clicking a row learns the right talent.
--
-- Geometry is real: wow_layout.lua resolves anchors the way the client does
-- and measures strings with the client's own font (fontmetrics.lua), so
-- GetStringHeight is the number WoW would give and a panel that is too short
-- for its own contents can be caught. Sim.Dump writes the resolved rectangles
-- out for render.py, which draws them with that same font.
--
-- Load order: trees.lua, fontmetrics.lua, wow_layout.lua, then this.
--
-- What it still is not: a renderer. Blizzard's backdrop art, template insets,
-- glyph kerning and strata are not modelled, so this answers "does this fit,
-- does it overlap, what does it say" and never "is it pretty".

----------------------------------------------------------------------------
-- World
----------------------------------------------------------------------------

World = {
    class = "SHAMAN", className = "Shaman",
    level = 10,
    unspent = 1,
    group = 1,
    ranks = {},          -- ["tab:tier:col"] = rank
    spent = { 0, 0, 0 },
    equipped = {},       -- [invSlot] = item key
    bags = {},           -- [bag] = { [slot] = item key }
    bagSize = 16,
    items = {},          -- [key] = { ... }
    useItemStats = true, -- false makes the addon fall back to the tooltip
    combat = false,
    learned = {},        -- LearnTalent calls, in order
    equipCalls = {},     -- {bag, slot, invSlot} per Equip
    cursor = nil,
}

local function talentList(tab)
    local tree = assert(TalentTrees[World.class], "no tree for " .. tostring(World.class))
    return assert(tree[tab], "no tab " .. tab).talents
end

local function rankKey(tab, tier, col) return tab .. ":" .. tier .. ":" .. col end

-- Put points in the way the game would, without checking gates: tests that
-- want an illegal state should be able to build one.
function World.SetRank(tab, tier, col, rank)
    local had = World.ranks[rankKey(tab, tier, col)] or 0
    World.ranks[rankKey(tab, tier, col)] = rank
    World.spent[tab] = World.spent[tab] + (rank - had)
end

-- UnitClass returns both, and the addon puts the display name in the picker's
-- title, so the two have to stay in step.
local function displayName(class)
    return class:sub(1, 1) .. class:sub(2):lower()
end

function World.Reset(class, level)
    World.class = class or "SHAMAN"
    World.className = displayName(World.class)
    World.level = level or 10
    World.unspent = level and (level - 9) or 1
    World.ranks, World.spent = {}, { 0, 0, 0 }
    World.equipped, World.bags, World.items = {}, {}, {}
    World.learned, World.equipCalls = {}, {}
    World.useItemStats, World.combat, World.cursor = true, false, nil
    TalentAdvisorDB, TalentAdvisorCharDB = nil, nil
    CHAT = {}
    -- The addon is loaded once and its state outlives a scenario; the parts
    -- that would otherwise leak between them are cleared here.
    if TalentAdvisor and TalentAdvisor.state then
        local st = TalentAdvisor.state
        st.build, st.plan, st.buildKey, st.talents, st.analysis = nil, nil, nil, nil, nil
        st.upgrades, st.announced, st.worn = {}, {}, nil
        st.dirtyGear, st.pendingItems = false, false
    end
end

-- key is what a link looks like: the addon parses "item:<id>" out of it.
function World.AddItem(key, def)
    def.key = key
    def.link = "|cffffffff|Hitem:" .. (def.id or 1) .. ":0:0:0|h[" .. (def.name or key) .. "]|h|r"
    World.items[key] = def
    return def
end

function World.Equip(invSlot, key) World.equipped[invSlot] = key end

function World.PutInBag(bag, slot, key)
    World.bags[bag] = World.bags[bag] or {}
    World.bags[bag][slot] = key
end

local function itemOf(key) return key and World.items[key] or nil end

local function itemByLink(link)
    for _, def in pairs(World.items) do if def.link == link then return def end end
    return nil
end

----------------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget

local function newWidget(kind, name, parent)
    local w = setmetatable({
        -- Every field the simulator keeps is prefixed: an addon may store
        -- anything it likes on a frame, and TalentAdvisor really does put its
        -- own font strings in row.name and row.text.
        _kind = kind, _name = name, _parent = parent,
        _points = {}, _scripts = {}, _events = {},
        _shown = true, _width = 0, _height = 0, _text = nil,
        _color = nil, _children = {}, _justify = "LEFT",
    }, Widget)
    if name then _G[name] = w end
    if parent and parent._children then parent._children[#parent._children + 1] = w end
    Layout.Invalidate()
    return w
end

function Widget:SetPoint(point, rel, relPoint, x, y)
    -- SetPoint("TOP", parentFrame, "BOTTOM", 0, -2) and SetPoint("TOP", 0, -2)
    if type(rel) == "number" or rel == nil then
        point, rel, relPoint, x, y = point, self._parent, point, rel, relPoint
    end
    self._points[#self._points + 1] = {
        point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0,
    }
    Layout.Invalidate()
end
function Widget:ClearAllPoints() self._points = {}; Layout.Invalidate() end
function Widget:GetPoint()
    local p = self._points[1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function Widget:GetNumPoints() return #self._points end
function Widget:SetAllPoints(rel)
    self._points[#self._points + 1] = { point = "ALL", rel = rel or self._parent }
    Layout.Invalidate()
end

function Widget:SetWidth(v) self._width = v; Layout.Invalidate() end
function Widget:SetHeight(v) self._height = v; Layout.Invalidate() end
function Widget:GetWidth() local l, r = Layout.RectX(self); return r - l end
function Widget:GetHeight() local b, t = Layout.RectY(self); return t - b end
-- left, bottom, right, top, in UIParent coordinates
function Widget:GetRect() return Layout.Rect(self) end

function Widget:Show() self._shown = true; Layout.Invalidate() end
function Widget:Hide() self._shown = false; Layout.Invalidate() end
function Widget:IsShown() return self._shown end
function Widget:IsVisible()
    local w = self
    while w do
        if not w._shown then return false end
        w = w._parent
    end
    return true
end

function Widget:SetText(t) self._text = t; Layout.Invalidate() end
function Widget:GetText() return self._text end
function Widget:SetTextColor(r, g, b) self._color = { r, g, b } end
function Widget:GetTextColor()
    local c = self._color or { 1, 1, 1 }
    return c[1], c[2], c[3]
end
function Widget:GetStringHeight() return Layout.TextHeight(self) end
function Widget:GetStringWidth()
    local size = Layout.FontSize(self)
    local widest = 0
    for _, line in ipairs(Layout.Wrap(self._text, size, nil)) do
        widest = math.max(widest, Layout.Width(line, size))
    end
    return widest
end
function Widget:SetJustifyH(h) self._justify = h end
function Widget:SetTexture(...) self._texture = { ... } end
function Widget:SetFontObject(f) self._font = f; Layout.Invalidate() end
function Widget:SetBackdrop(b) self._backdrop = b end
function Widget:SetBackdropColor(r, g, b, a) self._backdropColor = { r, g, b, a or 1 } end
function Widget:EnableMouse() end
function Widget:SetMovable() end
function Widget:SetClampedToScreen() end
function Widget:SetFrameStrata() end
function Widget:RegisterForDrag() end
function Widget:RegisterForClicks() end
function Widget:StartMoving() end
function Widget:StopMovingOrSizing() end
function Widget:SetScript(which, fn) self._scripts[which] = fn end
function Widget:GetScript(which) return self._scripts[which] end
function Widget:RegisterEvent(e) self._events[e] = true end
function Widget:UnregisterEvent(e) self._events[e] = nil end
function Widget:IsEventRegistered(e) return self._events[e] == true end
function Widget:SetOwner() end

function Widget:CreateFontString(name, layer, font)
    local w = newWidget("FontString", name, self)
    w._layer, w._font = layer, font
    return w
end
function Widget:CreateTexture(name, layer)
    local w = newWidget("Texture", name, self)
    w._layer = layer
    return w
end

-- Fire a script the way the client would.
function Widget:Fire(which, ...)
    local fn = self._scripts[which]
    if not fn then return nil end
    return fn(self, ...)
end
function Widget:Click() return self:Fire("OnClick") end

----------------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------------

local function makeTooltip(name, parent)
    local tip = newWidget("GameTooltip", name, parent)
    tip._lines = {}
    tip._left, tip._right = {}, {}
    for i = 1, 30 do
        tip._left[i] = newWidget("FontString", name .. "TextLeft" .. i, tip)
        tip._right[i] = newWidget("FontString", name .. "TextRight" .. i, tip)
    end
    function tip:ClearLines()
        self.count = 0
        for i = 1, 30 do
            self._left[i]:SetText(nil); self._left[i]._color = nil
            self._right[i]:SetText(nil); self._right[i]._color = nil
        end
    end
    function tip:NumLines() return self.count or 0 end
    function tip:AddLine() end
    function tip:Show() end
    function tip:Hide() end
    -- Lay an item's tooltip out the way the client would: the name, then the
    -- lines the item's def asks for, then the speed on the right of the
    -- damage line, and a red line when it cannot be used.
    function tip:Render(def)
        self:ClearLines()
        local n = 0
        local function line(left, right, red)
            n = n + 1
            self._left[n]:SetText(left)
            if red then self._left[n]:SetTextColor(1, 0.1, 0.1) else self._left[n]:SetTextColor(1, 1, 1) end
            if right then self._right[n]:SetText(right); self._right[n]:SetTextColor(1, 1, 1) end
        end
        line(def.name or "?")
        if def.stats and def.stats.DPS then
            line(string.format("%d - %d Damage", 10, 20),
                 def.speed and string.format("Speed %.2f", def.speed) or nil)
            line(string.format("(%.1f damage per second)", def.stats.DPS))
        end
        for _, t in ipairs(def.tooltip or {}) do line(t) end
        if def.usable == false then line("Requires Level 80", nil, true) end
        self.count = n
    end
    function tip:SetBagItem(bag, slot)
        local def = itemOf(World.bags[bag] and World.bags[bag][slot])
        if def then self:Render(def) else self:ClearLines() end
    end
    function tip:SetInventoryItem(_, inv)
        local def = itemOf(World.equipped[inv])
        if def then self:Render(def) else self:ClearLines() end
    end
    tip:ClearLines()
    return tip
end

----------------------------------------------------------------------------
-- Globals the addon reaches for
----------------------------------------------------------------------------

_G = _G or getfenv(0)

UIParent = newWidget("Frame", "UIParent", nil)
UIParent._width, UIParent._height = 1024, 768
SCREEN = { width = 1024, height = 768 }

-- The size a template brings with it, for the two the addon uses.
local TEMPLATE_SIZE = {
    UIPanelCloseButton = { 32, 32 },
    UIPanelButtonTemplate = { 40, 22 },
}

FRAMES = {}
function CreateFrame(kind, name, parent, template)
    local w
    if kind == "GameTooltip" or (template and template:find("GameTooltip")) then
        w = makeTooltip(name or ("Tooltip" .. #FRAMES), parent or UIParent)
    else
        w = newWidget(kind, name, parent or UIParent)
    end
    w._template = template
    local size = template and TEMPLATE_SIZE[template]
    if size then w._width, w._height = size[1], size[2] end
    if kind == "Button" then w._font = w._font or "GameFontNormalSmall" end
    FRAMES[#FRAMES + 1] = w
    return w
end

GameTooltip = makeTooltip("GameTooltip", UIParent)

CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }
SlashCmdList = {}

function InCombatLockdown() return World.combat end
function UnitClass() return World.className, World.class end
function UnitLevel() return World.level end
function UnitCharacterPoints() return World.unspent end
function GetActiveTalentGroup() return World.group end

function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(tab)
    local tree = TalentTrees[World.class]
    if not tree or not tree[tab] then return nil end
    return tree[tab].name, nil, World.spent[tab]
end
function GetNumTalents(tab) return #talentList(tab) end
function GetTalentInfo(tab, index)
    local row = talentList(tab)[index]
    if not row then return nil end
    local tier, col, max, name = row[1], row[2], row[3], row[4]
    return name, "Interface\\Icons\\" .. name, tier, col,
        World.ranks[rankKey(tab, tier, col)] or 0, max
end
function LearnTalent(tab, index)
    local row = assert(talentList(tab)[index], "LearnTalent on a talent that is not there")
    local key = rankKey(tab, row[1], row[2])
    assert((World.ranks[key] or 0) < row[3], "LearnTalent past the rank cap on " .. row[4])
    assert(World.unspent > 0, "LearnTalent with no point to spend")
    World.ranks[key] = (World.ranks[key] or 0) + 1
    World.spent[tab] = World.spent[tab] + 1
    World.unspent = World.unspent - 1
    World.learned[#World.learned + 1] = { tab = tab, index = index, name = row[4] }
end

function GetInventoryItemLink(_, inv)
    local def = itemOf(World.equipped[inv])
    return def and def.link or nil
end
function GetContainerNumSlots(bag) return World.bags[bag] and World.bagSize or 0 end
function GetContainerItemLink(bag, slot)
    local def = itemOf(World.bags[bag] and World.bags[bag][slot])
    return def and def.link or nil
end

function GetItemInfo(link)
    local def = itemByLink(link)
    if not def then return nil end
    if def.uncached then return nil end        -- "not in the client cache yet"
    return def.name, def.link, def.quality or 2, 0, def.minLevel or 1,
        def.itemType or "Armor", def.subType or "Mail", 1, def.equipLoc
end

-- The client only has this from 3.1 on; a test can take it away to make the
-- addon walk the tooltip instead.
function GetItemStats(link)
    if not World.useItemStats then return nil end
    local def = itemByLink(link)
    if not def then return nil end
    local out = {}
    for stat, v in pairs(def.stats or {}) do
        if stat == "DPS" then
            out.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = v
        elseif stat == "ARMOR" then
            out.RESISTANCE0_NAME = v
        else
            local key = "ITEM_MOD_" .. stat .. "_SHORT"
            for g, s in pairs(TalentAdvisor and TalentAdvisor.STAT_KEYS or {}) do
                if s == stat then key = g; break end
            end
            out[key] = v
        end
    end
    return out
end

function ClearCursor() World.cursor = nil end
function PickupContainerItem(bag, slot) World.cursor = { bag = bag, slot = slot } end
function CursorHasItem() return World.cursor ~= nil end
function EquipCursorItem(invSlot)
    local c = assert(World.cursor, "EquipCursorItem with an empty cursor")
    World.equipCalls[#World.equipCalls + 1] = { bag = c.bag, slot = c.slot, invSlot = invSlot }
    local key = World.bags[c.bag][c.slot]
    World.bags[c.bag][c.slot] = World.equipped[invSlot]
    World.equipped[invSlot] = key
    World.cursor = nil
end

MODIFIED_CLICK = nil
function IsModifiedClick(what) return MODIFIED_CLICK == what end
function ChatEdit_InsertLink(link) CHAT[#CHAT + 1] = "LINK:" .. link end

-- Format strings the tooltip fallback turns into patterns.
SPEED = "Speed"
RESISTANCE0_NAME = "Armor"
ITEM_MOD_STRENGTH_SHORT = "Strength"
ITEM_MOD_AGILITY_SHORT = "Agility"
ITEM_MOD_STAMINA_SHORT = "Stamina"
ITEM_MOD_INTELLECT_SHORT = "Intellect"
ITEM_MOD_SPIRIT_SHORT = "Spirit"
ITEM_MOD_ATTACK_POWER = "Increases attack power by %d."
ITEM_MOD_CRIT_RATING = "Improves critical strike rating by %d."
ITEM_MOD_HIT_RATING = "Improves hit rating by %d."
ITEM_MOD_HASTE_RATING = "Improves haste rating by %d."
ITEM_MOD_CRIT_SPELL_RATING = "Improves spell critical strike rating by %d."
ITEM_MOD_HIT_SPELL_RATING = "Improves spell hit rating by %d."
ITEM_MOD_HASTE_SPELL_RATING = "Improves spell haste rating by %d."
ITEM_MOD_CRIT_MELEE_RATING = "Improves melee critical strike rating by %d."
ITEM_MOD_HIT_MELEE_RATING = "Improves melee hit rating by %d."
ITEM_MOD_HASTE_MELEE_RATING = "Improves melee haste rating by %d."
ITEM_MOD_EXPERTISE_RATING = "Increases your expertise rating by %d."
ITEM_MOD_ARMOR_PENETRATION_RATING = "Increases armor penetration rating by %d."
ITEM_MOD_SPELL_POWER = "Increases spell power by %d."
ITEM_MOD_MANA_REGENERATION = "Restores %d mana per 5 sec."
ITEM_MOD_HEALTH_REGENERATION = "Restores %d health per 5 sec."
ITEM_MOD_DEFENSE_SKILL_RATING = "Increases defense rating by %d."
ITEM_MOD_DODGE_RATING = "Increases your dodge rating by %d."
ITEM_MOD_PARRY_RATING = "Increases your parry rating by %d."
ITEM_MOD_BLOCK_RATING = "Increases your shield block rating by %d."
ITEM_MOD_BLOCK_VALUE = "Increases the block value of your shield by %d."
ITEM_MOD_RESILIENCE_RATING = "Improves your resilience rating by %d."

----------------------------------------------------------------------------
-- Driving the addon
----------------------------------------------------------------------------

Sim = {}

-- The event frame the addon made for itself: the last frame that registered
-- PLAYER_LOGIN.
function Sim.Events()
    for i = #FRAMES, 1, -1 do
        if FRAMES[i]._events and FRAMES[i]._events["PLAYER_LOGIN"] then return FRAMES[i] end
    end
    error("the addon never registered PLAYER_LOGIN")
end

function Sim.Event(event, ...)
    return Sim.Events():Fire("OnEvent", event, ...)
end

-- Run the debounced bag scan to completion, the way a second of game time
-- would. Errors if it never settles.
function Sim.Tick(seconds)
    local ev = Sim.Events()
    for _ = 1, 20 do
        ev:Fire("OnUpdate", seconds or 1.0)
        if not TalentAdvisor.state.dirtyGear then return end
    end
    error("the gear scan never settled")
end

function Sim.Login()
    Sim.Event("PLAYER_LOGIN")
    Sim.Tick()
end

function Sim.Slash(cmd) SlashCmdList.TALENTADVISOR(cmd) end

function Sim.Frame() return _G["TalentAdvisorFrame"] end
function Sim.Picker() return _G["TalentAdvisorPicker"] end

-- The picker rows that are actually on screen, in order.
function Sim.PickerRows()
    local p = Sim.Picker()
    local out = {}
    if not p then return out end
    for _, row in ipairs(p.rows or {}) do
        if row:IsShown() and row.buildKey then out[#out + 1] = row end
    end
    return out
end

function Sim.PickerHeaders()
    local p = Sim.Picker()
    local out = {}
    if not p then return out end
    for _, h in ipairs(p.headers or {}) do
        if h:IsShown() then out[#out + 1] = h:GetText() end
    end
    return out
end

function Sim.GearRows()
    local f = Sim.Frame()
    local out = {}
    if not f then return out end
    for _, row in ipairs(f.rows or {}) do
        if row:IsShown() and row.upgrade then out[#out + 1] = row end
    end
    return out
end

function Sim.Chat() return table.concat(CHAT, "\n") end
function Sim.ChatHas(needle) return Sim.Chat():find(needle, 1, true) ~= nil end

----------------------------------------------------------------------------
-- Snapshots
----------------------------------------------------------------------------

-- The resolved layout, written out for render.py to draw. Only what is
-- actually on screen: a widget whose parent is hidden is not in the file, the
-- same way it is not in the game.

local function jsonString(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == '\\' then return '\\\\'
        elseif c == '\n' then return '\\n' elseif c == '\r' then return '\\r'
        elseif c == '\t' then return '\\t' end
        return string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function jsonValue(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then return string.format("%.3f", v)
    elseif t == "string" then return jsonString(v)
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for _, item in ipairs(v) do out[#out + 1] = jsonValue(item) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = jsonString(k) .. ":" .. jsonValue(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

local function describe(w, out)
    if not w._shown then return end
    local l, b, r, t = Layout.Rect(w)
    local entry = {
        kind = w._kind, name = w._name or "", template = w._template or "",
        font = w._font or "", size = Layout.FontSize(w), layer = w._layer or "",
        justify = w._justify or "LEFT",
        left = l, bottom = b, right = r, top = t,
        text = w._text or "", visible = Layout.Visible(w._text),
    }
    if w._color then entry.color = { w._color[1], w._color[2], w._color[3] } end
    if w._backdrop then
        entry.backdrop = tostring(w._backdrop.edgeFile or "")
        local c = w._backdropColor or { 0, 0, 0, 0.85 }
        entry.backdropColor = { c[1], c[2], c[3], c[4] }
    end
    if w._texture then
        local tex = {}
        for i, v in ipairs(w._texture) do tex[i] = tostring(v) end
        entry.texture = tex
    end
    if w._kind == "FontString" and (w._text or "") ~= "" then
        -- coloured runs, so the picture keeps the "(meta)" orange and the
        -- "+12%" green that the layout only ever saw as characters
        local lines = {}
        for _, runs in ipairs(Layout.WrapRuns(w._text, Layout.FontSize(w), r - l)) do
            local out = {}
            for _, run in ipairs(runs) do
                out[#out + 1] = { text = run.text, color = run.color }
            end
            lines[#lines + 1] = out
        end
        entry.lines = lines
    end
    out[#out + 1] = entry
    for _, child in ipairs(w._children) do describe(child, out) end
end

-- roots: the frames to draw, in order. Defaults to everything under UIParent
-- that is showing.
function Sim.Snapshot(roots)
    local out = {}
    for _, w in ipairs(roots or UIParent._children) do
        if w:IsShown() then describe(w, out) end
    end
    return { screen = { width = SCREEN.width, height = SCREEN.height }, widgets = out }
end

function Sim.Dump(path, roots)
    local f = assert(io.open(path, "w"))
    f:write(jsonValue(Sim.Snapshot(roots)))
    f:close()
    return path
end

-- Every showing widget under a frame, the frame itself first.
function Sim.Tree(w, out)
    out = out or {}
    if not w._shown then return out end
    out[#out + 1] = w
    for _, child in ipairs(w._children) do Sim.Tree(child, out) end
    return out
end
