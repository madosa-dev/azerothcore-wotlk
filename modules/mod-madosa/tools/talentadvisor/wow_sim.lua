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
-- What it deliberately does not simulate: pixels. Fonts have no metrics here,
-- so GetStringHeight is an estimate and layout can only be checked for sanity
-- (anchored to something, positive height), never for looks.

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

function World.Reset(class, level)
    World.class = class or "SHAMAN"
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
        kind = kind, name = name, parent = parent,
        points = {}, scripts = {}, events = {},
        shown = true, width = 0, height = 0, text = nil,
        color = nil, children = {},
    }, Widget)
    if name then _G[name] = w end
    if parent and parent.children then parent.children[#parent.children + 1] = w end
    return w
end

function Widget:SetPoint(point, rel, relPoint, x, y)
    -- SetPoint("TOP", parentFrame, "BOTTOM", 0, -2) and SetPoint("TOP", 0, -2)
    if type(rel) == "number" then point, rel, relPoint, x, y = point, self.parent, point, rel, relPoint end
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetPoint()
    local p = self.points[1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function Widget:GetNumPoints() return #self.points end
function Widget:SetAllPoints() self.points[#self.points + 1] = { point = "ALL" } end

function Widget:SetWidth(v) self.width = v end
function Widget:SetHeight(v) self.height = v end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end

function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end

function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
function Widget:GetTextColor()
    local c = self.color or { 1, 1, 1 }
    return c[1], c[2], c[3]
end
-- No font metrics here: enough for "did the layout get a sensible number".
function Widget:GetStringHeight()
    local t = self.text
    if not t or t == "" then return 0 end
    local width = self.width
    if width == 0 and self.parent then width = self.parent.width - 32 end
    if width <= 0 then width = 200 end
    return 12 * math.max(1, math.ceil(#t / math.max(20, width / 6)))
end
function Widget:SetJustifyH() end
function Widget:SetTexture(...) self.texture = { ... } end
function Widget:SetBackdrop() end
function Widget:SetBackdropColor() end
function Widget:EnableMouse() end
function Widget:SetMovable() end
function Widget:SetClampedToScreen() end
function Widget:SetFrameStrata() end
function Widget:RegisterForDrag() end
function Widget:RegisterForClicks() end
function Widget:StartMoving() end
function Widget:StopMovingOrSizing() end
function Widget:SetScript(which, fn) self.scripts[which] = fn end
function Widget:GetScript(which) return self.scripts[which] end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:IsEventRegistered(e) return self.events[e] == true end
function Widget:SetOwner() end

function Widget:CreateFontString(name, _, _)
    return newWidget("FontString", name, self)
end
function Widget:CreateTexture(name) return newWidget("Texture", name, self) end

-- Fire a script the way the client would.
function Widget:Fire(which, ...)
    local fn = self.scripts[which]
    if not fn then return nil end
    return fn(self, ...)
end
function Widget:Click() return self:Fire("OnClick") end

----------------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------------

local function makeTooltip(name, parent)
    local tip = newWidget("GameTooltip", name, parent)
    tip.lines = {}
    tip.left, tip.right = {}, {}
    for i = 1, 30 do
        tip.left[i] = newWidget("FontString", name .. "TextLeft" .. i, tip)
        tip.right[i] = newWidget("FontString", name .. "TextRight" .. i, tip)
    end
    function tip:ClearLines()
        self.count = 0
        for i = 1, 30 do
            self.left[i]:SetText(nil); self.left[i].color = nil
            self.right[i]:SetText(nil); self.right[i].color = nil
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
            self.left[n]:SetText(left)
            if red then self.left[n]:SetTextColor(1, 0.1, 0.1) else self.left[n]:SetTextColor(1, 1, 1) end
            if right then self.right[n]:SetText(right); self.right[n]:SetTextColor(1, 1, 1) end
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
UIParent.width, UIParent.height = 1024, 768

FRAMES = {}
function CreateFrame(kind, name, parent, template)
    local w
    if kind == "GameTooltip" or (template and template:find("GameTooltip")) then
        w = makeTooltip(name or ("Tooltip" .. #FRAMES), parent or UIParent)
    else
        w = newWidget(kind, name, parent or UIParent)
    end
    w.template = template
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
        if FRAMES[i].events and FRAMES[i].events["PLAYER_LOGIN"] then return FRAMES[i] end
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
        if row.shown and row.buildKey then out[#out + 1] = row end
    end
    return out
end

function Sim.PickerHeaders()
    local p = Sim.Picker()
    local out = {}
    if not p then return out end
    for _, h in ipairs(p.headers or {}) do
        if h.shown then out[#out + 1] = h:GetText() end
    end
    return out
end

function Sim.GearRows()
    local f = Sim.Frame()
    local out = {}
    if not f then return out end
    for _, row in ipairs(f.rows or {}) do
        if row.shown and row.upgrade then out[#out + 1] = row end
    end
    return out
end

function Sim.Chat() return table.concat(CHAT, "\n") end
function Sim.ChatHas(needle) return Sim.Chat():find(needle, 1, true) ~= nil end
