-- TalentAdvisor: where the next talent point goes, and which item in the bags
-- beats what is worn, for one levelling build per class (Builds.lua).
--
-- Talents
-- -------
-- The build is an ordered list of (tab, tier, column, points). What the
-- player actually has is read with GetTalentInfo() and the two are walked
-- together: the first plan step whose talent has fewer ranks than the plan
-- has handed out by then is the next point. That is deliberately not "plan
-- entry number (level - 9)": a point put somewhere else, a respec, or a
-- point saved up for a few levels all leave the walk pointing at the right
-- place, and whatever was spent outside the plan is listed separately
-- instead of being silently counted.
--
-- Each pick also carries whether its tier is open. Tier N needs 5*(N-1)
-- points in that tree; the walk simulates the points it is about to
-- recommend, so a queue of several picks is gated correctly as a whole.
--
-- LearnTalent() is not protected on 3.3.5, so the frame's button (and, if
-- switched on, the level-up handler) can place the point itself.
--
-- Gear
-- ----
-- Every equippable item in the bags is scored with the build's stat weights
-- and compared with what is in the slot it would go to. Stats come from
-- GetItemStats() where the client has it, else from the tooltip; the tooltip
-- is read anyway for weapon speed, and for the one check that decides
-- usability: any red line means the item cannot be worn right now (level,
-- class, skill, faction - all of them colour that way), which is both exact
-- and independent of client language.
--
-- Weapons are compared as a set. A two-hander is weighed against main hand
-- plus off hand together; a one-hander is tried as the main hand with the
-- current off hand, and - once the build's dual-wield talent is known - as
-- the off hand next to the current main hand, and the better of the two
-- placements counts. Rings and trinkets replace the weaker of their two
-- slots. Nothing is suggested unless it beats the worn piece by a margin
-- (default 3%), so re-scans do not flip between near-equal items.
--
-- Everything pure - plan expansion, the walk, scoring, set comparison - is
-- on the TalentAdvisor table and takes plain data, so tools/talentadvisor/
-- runs it under lua5.1 without a client.

TalentAdvisor = TalentAdvisor or {}
local TA = TalentAdvisor
local BUILDS = TalentAdvisorBuilds

local PREFIX = "|cff33ccffTalentAdvisor|r: "
local UPGRADE_MARGIN = 1.03      -- candidate must beat the worn score by this factor
local MAX_ROWS = 6               -- gear rows in the frame
local RESCAN_DELAY = 0.6         -- seconds of bag quiet before a rescan
local NEXT_PICKS = 4             -- picks shown in the frame

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
end
TA.Print = Print

local function Key(tab, tier, col) return tab .. ":" .. tier .. ":" .. col end
TA.Key = Key

----------------------------------------------------------------------------
-- Plan
----------------------------------------------------------------------------

-- {tab,tier,col,points} steps -> one entry per point, in order.
function TA.ExpandPlan(build)
    local plan = {}
    for _, step in ipairs(build.steps) do
        for _ = 1, step[4] do
            plan[#plan + 1] = { tab = step[1], tier = step[2], col = step[3] }
        end
    end
    return plan
end

-- Plan entry i is the point earned at level 9 + i, if nothing was skipped.
function TA.PlanLevel(i) return 9 + i end

-- Snapshot of the player's talents:
--   byKey[tab:tier:col] = { name, icon, tier, col, rank, maxRank, tab, index }
--   points[tab]         = points spent in that tree
--   tabs[tab]           = tree name
function TA.ReadTalents()
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or nil
    local t = { byKey = {}, points = {}, tabs = {} }
    for tab = 1, GetNumTalentTabs() do
        local tabName, _, spent = GetTalentTabInfo(tab, nil, nil, group)
        t.tabs[tab] = tabName
        t.points[tab] = spent or 0
        for index = 1, GetNumTalents(tab) do
            local name, icon, tier, col, rank, maxRank = GetTalentInfo(tab, index, nil, nil, group)
            if name then
                t.byKey[Key(tab, tier, col)] = {
                    name = name, icon = icon, tier = tier, col = col,
                    rank = rank or 0, maxRank = maxRank or 0, tab = tab, index = index,
                }
            end
        end
    end
    return t
end

-- Walk plan against talents. Returns
--   picks   : up to `count` next points, each { key, talent, rank, planIndex,
--             level, blocked, need } - blocked when the tier is not open yet,
--             need = points still missing in that tree for it
--   offPlan : talents holding more ranks than the whole plan gives them
--   unknown : plan steps naming a talent the tree does not have (wrong class
--             or a mistyped build) - anything here means the build is broken
--   spent / total : points placed so far / points the plan has
function TA.Analyse(plan, talents, count)
    count = count or NEXT_PICKS
    local picks, offPlan, unknown = {}, {}, {}
    local plannedSoFar, plannedTotal = {}, {}
    local simRank, simPoints = {}, {}
    for tab, n in pairs(talents.points) do simPoints[tab] = n end

    for _, step in ipairs(plan) do
        local k = Key(step.tab, step.tier, step.col)
        plannedTotal[k] = (plannedTotal[k] or 0) + 1
    end

    for i, step in ipairs(plan) do
        local k = Key(step.tab, step.tier, step.col)
        plannedSoFar[k] = (plannedSoFar[k] or 0) + 1
        local talent = talents.byKey[k]
        if not talent then
            if not unknown[k] then unknown[k] = true; unknown[#unknown + 1] = k end
        elseif #picks < count then
            local have = simRank[k] or talent.rank
            if have < plannedSoFar[k] then
                local gate = 5 * (step.tier - 1)
                local inTab = simPoints[step.tab] or 0
                picks[#picks + 1] = {
                    key = k, talent = talent, rank = have + 1, planIndex = i,
                    level = TA.PlanLevel(i),
                    blocked = inTab < gate, need = math.max(0, gate - inTab),
                }
                simRank[k] = have + 1
                simPoints[step.tab] = inTab + 1
            end
        end
    end

    for k, talent in pairs(talents.byKey) do
        local extra = talent.rank - (plannedTotal[k] or 0)
        if extra > 0 then offPlan[#offPlan + 1] = { talent = talent, extra = extra } end
    end
    table.sort(offPlan, function(a, b) return a.talent.name < b.talent.name end)

    local spent = 0
    for _, n in pairs(talents.points) do spent = spent + n end
    return { picks = picks, offPlan = offPlan, unknown = unknown, spent = spent, total = #plan }
end

----------------------------------------------------------------------------
-- Items: reading
----------------------------------------------------------------------------

-- GetItemStats() keys -> the stat names the weights use.
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI",
    ITEM_MOD_STAMINA_SHORT = "STA", ITEM_MOD_INTELLECT_SHORT = "INT",
    ITEM_MOD_SPIRIT_SHORT = "SPI", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
    ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "EXP",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCK", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
    RESISTANCE0_NAME = "ARMOR",
}
TA.STAT_KEYS = STAT_KEYS

-- Tooltip fallback when GetItemStats() is missing: the game's own format
-- strings, turned into patterns. "+%d Stamina" style lines use the *_SHORT
-- names, "Equip: Increases attack power by %d." lines the long ones.
local LINE_PATTERNS
local function BuildLinePatterns()
    LINE_PATTERNS = {}
    local function pat(fmt)
        fmt = fmt:gsub("%%c", ""):gsub("%%d", "\1"):gsub("%%s", "\1")
        fmt = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        return (fmt:gsub("\1", "(%%d+)"))
    end
    local long = {
        ITEM_MOD_ATTACK_POWER = "AP", ITEM_MOD_CRIT_RATING = "CRIT", ITEM_MOD_CRIT_MELEE_RATING = "CRIT",
        ITEM_MOD_HIT_RATING = "HIT", ITEM_MOD_HIT_MELEE_RATING = "HIT", ITEM_MOD_HASTE_RATING = "HASTE",
        ITEM_MOD_HASTE_MELEE_RATING = "HASTE", ITEM_MOD_EXPERTISE_RATING = "EXP",
        ITEM_MOD_ARMOR_PENETRATION_RATING = "ARP", ITEM_MOD_SPELL_POWER = "SP",
        ITEM_MOD_MANA_REGENERATION = "MP5", ITEM_MOD_BLOCK_VALUE = "BLOCK",
    }
    for global, stat in pairs(long) do
        local fmt = _G[global]
        if type(fmt) == "string" and fmt:find("%%") then
            LINE_PATTERNS[#LINE_PATTERNS + 1] = { pat(fmt), stat }
        end
    end
    for global, stat in pairs({ ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI",
        ITEM_MOD_STAMINA_SHORT = "STA", ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI" }) do
        local word = _G[global]
        if type(word) == "string" then
            LINE_PATTERNS[#LINE_PATTERNS + 1] = { "^%+(%d+) " .. pat(word) .. "$", stat }
        end
    end
end

-- Hidden tooltip for scanning.
local scanTip
local function ScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TalentAdvisorScanTip", UIParent, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    return scanTip
end

local function IsRed(r, g, b)
    return r and r > 0.9 and g < 0.2 and b < 0.2
end

-- Read the tooltip currently set on the scan tip: speed, DPS, whether a red
-- line says it cannot be used, and stat lines for the fallback.
local function ReadTip(stats, needStats)
    local speedWord = (SPEED or "Speed")
    local info = { usable = true }
    for i = 1, scanTip:NumLines() do
        local left = _G["TalentAdvisorScanTipTextLeft" .. i]
        local right = _G["TalentAdvisorScanTipTextRight" .. i]
        local lt = left and left:GetText()
        local rt = right and right:GetText()
        if lt then
            if IsRed(left:GetTextColor()) then info.usable = false end
            local dps = lt:match("%(([%d%.,]+) ") -- "(12.3 damage per second)"
            if dps and lt:find("second") then info.dps = tonumber((dps:gsub(",", "."))) end
            if needStats and LINE_PATTERNS then
                for _, p in ipairs(LINE_PATTERNS) do
                    local v = lt:match(p[1])
                    if v then stats[p[2]] = (stats[p[2]] or 0) + tonumber(v); break end
                end
            end
        end
        if rt then
            if IsRed(right:GetTextColor()) then info.usable = false end
            local sp = rt:match("^" .. speedWord .. "%s+([%d%.,]+)$")
            if sp then info.speed = tonumber((sp:gsub(",", "."))) end
        end
    end
    return info
end

-- One item, from a bag slot (bag, slot) or a worn slot (nil, invSlot).
-- nil when the item is not in the client cache yet.
function TA.ReadItem(link, bag, slot)
    if not link then return nil end
    local name, _, quality, _, minLevel, itemType, subType, _, equipLoc = GetItemInfo(link)
    if not name then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    local stats = {}
    local haveStats = false
    if type(GetItemStats) == "function" then
        local raw = GetItemStats(link)
        if raw then
            haveStats = true
            for k, v in pairs(raw) do
                local stat = STAT_KEYS[k]
                if stat then stats[stat] = (stats[stat] or 0) + v end
            end
        end
    end
    if not haveStats and not LINE_PATTERNS then BuildLinePatterns() end

    local tip = ScanTip()
    if bag then tip:SetBagItem(bag, slot) else tip:SetInventoryItem("player", slot) end
    local info = ReadTip(stats, not haveStats)
    if not stats.DPS and info.dps then stats.DPS = info.dps end

    return {
        link = link, id = id, name = name, quality = quality, minLevel = minLevel or 0,
        itemType = itemType, subType = subType, equipLoc = equipLoc or "",
        stats = stats, speed = info.speed, usable = info.usable,
    }
end

----------------------------------------------------------------------------
-- Items: scoring (pure)
----------------------------------------------------------------------------

-- hand: "MH", "OH", "2H" or nil for armour.
function TA.Score(item, weights, hand)
    if not item then return 0 end
    local s = 0
    for stat, v in pairs(item.stats) do
        if stat ~= "DPS" then s = s + (weights[stat] or 0) * v end
    end
    if hand and item.stats.DPS then
        s = s + item.stats.DPS * (weights["DPS_" .. hand] or 0)
        local speedW = weights["SPEED_" .. hand]
        if speedW and item.speed then s = s + math.max(0, item.speed - 2.0) * speedW end
    end
    return s
end

local ARMOUR_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
}
TA.ARMOUR_SLOTS = ARMOUR_SLOTS

local function IsTwoHand(item) return item and item.equipLoc == "INVTYPE_2HWEAPON" end
local function IsOneHand(item)
    return item and (item.equipLoc == "INVTYPE_WEAPON" or item.equipLoc == "INVTYPE_WEAPONMAINHAND"
        or item.equipLoc == "INVTYPE_WEAPONOFFHAND")
end

-- Score of the worn weapon set.
local function WornWeaponScore(worn, weights)
    local mh, oh = worn[16], worn[17]
    if IsTwoHand(mh) then return TA.Score(mh, weights, "2H") end
    local s = TA.Score(mh, weights, "MH")
    if oh then s = s + TA.Score(oh, weights, IsOneHand(oh) and "OH" or nil) end
    return s
end

-- Best placement of a weapon-slot candidate against what is worn.
-- Returns candidateSetScore, wornSetScore, slot (16 or 17), or nil if it
-- cannot go anywhere.
function TA.CompareWeapon(cand, worn, weights, canDualWield)
    local wornScore = WornWeaponScore(worn, weights)
    local mh, oh = worn[16], worn[17]
    local loc = cand.equipLoc
    local best, bestSlot

    if loc == "INVTYPE_2HWEAPON" then
        best, bestSlot = TA.Score(cand, weights, "2H"), 16
    else
        -- as main hand, keeping the current off hand (which a 2H would have displaced)
        if loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
            local s = TA.Score(cand, weights, "MH")
            if oh and not IsTwoHand(mh) then s = s + TA.Score(oh, weights, IsOneHand(oh) and "OH" or nil) end
            best, bestSlot = s, 16
        end
        -- as off hand next to the current main hand
        local ohOK = (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND") and canDualWield
            or loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE"
        if ohOK and mh and not IsTwoHand(mh) then
            local s = TA.Score(mh, weights, "MH") + TA.Score(cand, weights, IsOneHand(cand) and "OH" or nil)
            if not best or s > best then best, bestSlot = s, 17 end
        elseif ohOK and not mh then
            local s = TA.Score(cand, weights, IsOneHand(cand) and "OH" or nil)
            if not best or s > best then best, bestSlot = s, 17 end
        end
    end
    if not best then return nil end
    return best, wornScore, bestSlot
end

-- items: list of bag items ({ item = <ReadItem>, bag, slot }); worn: [invSlot] = item.
-- Returns list of { item, bag, slot, invSlot, score, wornScore, wornItem, gain }
function TA.FindUpgrades(items, worn, weights, canDualWield, margin)
    margin = margin or UPGRADE_MARGIN
    local out = {}
    local wornIds = {}
    for _, w in pairs(worn) do if w then wornIds[w.id] = true end end

    for _, entry in ipairs(items) do
        local it = entry.item
        if it and it.usable and not wornIds[it.id] then
            local slots = ARMOUR_SLOTS[it.equipLoc]
            if slots then
                -- the weaker of the possible slots is the one to replace
                local target, targetScore
                for _, inv in ipairs(slots) do
                    local s = TA.Score(worn[inv], weights)
                    if not target or s < targetScore then target, targetScore = inv, s end
                end
                local s = TA.Score(it, weights)
                if s > targetScore * margin + 0.5 then
                    out[#out + 1] = { item = it, bag = entry.bag, slot = entry.slot, invSlot = target,
                        score = s, wornScore = targetScore, wornItem = worn[target], gain = s - targetScore }
                end
            elseif it.equipLoc:find("^INVTYPE_") and (IsTwoHand(it) or IsOneHand(it)
                or it.equipLoc == "INVTYPE_SHIELD" or it.equipLoc == "INVTYPE_HOLDABLE") then
                local s, ws, inv = TA.CompareWeapon(it, worn, weights, canDualWield)
                if s and s > ws * margin + 0.5 then
                    out[#out + 1] = { item = it, bag = entry.bag, slot = entry.slot, invSlot = inv,
                        score = s, wornScore = ws, wornItem = worn[inv], gain = s - ws, weaponSet = true }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.gain > b.gain end)
    return out
end

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

local state = {
    build = nil, plan = nil, className = nil,
    talents = nil, analysis = nil, upgrades = {},
    announced = {},            -- item id -> true once its upgrade was printed
    pendingItems = false,      -- an item was not cached; rescan soon
}
TA.state = state

local function DB()
    TalentAdvisorDB = TalentAdvisorDB or {}
    local db = TalentAdvisorDB
    if db.auto == nil then db.auto = false end
    if db.margin == nil then db.margin = UPGRADE_MARGIN end
    if db.shown == nil then db.shown = true end
    return db
end

local function CharDB()
    TalentAdvisorCharDB = TalentAdvisorCharDB or {}
    return TalentAdvisorCharDB
end

function TA.SelectBuild(key)
    local _, class = UnitClass("player")
    state.className = class
    local set = BUILDS[class]
    if not set then state.build, state.plan = nil, nil; return false, "no build for " .. tostring(class) end
    key = key or CharDB().build or set.default
    local build = set[key]
    if type(build) ~= "table" or not build.steps then return false, "unknown build '" .. tostring(key) .. "'" end
    CharDB().build = key
    state.buildKey = key
    state.build = build
    state.plan = TA.ExpandPlan(build)
    return true
end

function TA.BuildKeys()
    local set = BUILDS[state.className]
    local keys = {}
    if set then
        for k, v in pairs(set) do if type(v) == "table" and v.steps then keys[#keys + 1] = k end end
    end
    table.sort(keys)
    return keys
end

local function CanDualWield()
    if not state.build or not state.build.dualWield or not state.talents then return false end
    local d = state.build.dualWield
    local t = state.talents.byKey[Key(d.tab, d.tier, d.col)]
    return t ~= nil and t.rank > 0
end

function TA.RefreshTalents()
    if not state.plan then return end
    state.talents = TA.ReadTalents()
    state.analysis = TA.Analyse(state.plan, state.talents, NEXT_PICKS)
end

function TA.RefreshGear()
    if not state.build then return end
    local worn = {}
    for inv = 1, 17 do
        local link = GetInventoryItemLink("player", inv)
        if link then
            local it = TA.ReadItem(link, nil, inv)
            if it then worn[inv] = it elseif link then state.pendingItems = true end
        end
    end
    local items = {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local it = TA.ReadItem(link, bag, slot)
                if it then
                    if it.equipLoc ~= "" then items[#items + 1] = { item = it, bag = bag, slot = slot } end
                else
                    state.pendingItems = true
                end
            end
        end
    end
    state.worn = worn
    state.upgrades = TA.FindUpgrades(items, worn, state.build.weights, CanDualWield(), DB().margin)
    for _, u in ipairs(state.upgrades) do
        if not state.announced[u.item.id] then
            state.announced[u.item.id] = true
            Print(string.format("%s beats %s (%+d%%) - click it in the advisor to equip.",
                u.item.link, u.wornItem and u.wornItem.link or "an empty slot",
                u.wornScore > 0 and math.floor((u.score / u.wornScore - 1) * 100 + 0.5) or 100))
        end
    end
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------

local function Unspent()
    local n = UnitCharacterPoints("player")
    return n or 0
end

function TA.LearnNext()
    if not state.analysis then return false end
    local pick = state.analysis.picks[1]
    if not pick then Print("The plan is complete."); return false end
    if Unspent() < 1 then Print("No talent point to spend."); return false end
    if pick.blocked then
        Print(string.format("%s is in tier %d - %d more point(s) in %s first.", pick.talent.name,
            pick.talent.tier, pick.need, state.talents.tabs[pick.talent.tab] or "that tree"))
        return false
    end
    LearnTalent(pick.talent.tab, pick.talent.index)
    Print(string.format("Learning %s (%d/%d).", pick.talent.name, pick.rank, pick.talent.maxRank))
    return true
end

function TA.Equip(u)
    if InCombatLockdown() then Print("Not in combat."); return end
    ClearCursor()
    PickupContainerItem(u.bag, u.slot)
    if CursorHasItem() then
        EquipCursorItem(u.invSlot)
    end
end

----------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------

local frame
local function BuildFrame()
    frame = CreateFrame("Frame", "TalentAdvisorFrame", UIParent)
    frame:SetWidth(300); frame:SetHeight(120)
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -120)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:EnableMouse(true); frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        DB().pos = { p, rp, x, y }
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetText("Talent Advisor")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 2, 2)
    frame.close:SetScript("OnClick", function() DB().shown = false; frame:Hide() end)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetWidth(28); frame.icon:SetHeight(28)
    frame.icon:SetPoint("TOPLEFT", 10, -26)

    frame.next = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.next:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 6, 0)
    frame.next:SetPoint("RIGHT", -70, 0)
    frame.next:SetJustifyH("LEFT")

    frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.sub:SetPoint("TOPLEFT", frame.next, "BOTTOMLEFT", 0, -2)
    frame.sub:SetPoint("RIGHT", -70, 0)
    frame.sub:SetJustifyH("LEFT")
    frame.sub:SetTextColor(0.8, 0.8, 0.8)

    frame.learn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.learn:SetWidth(56); frame.learn:SetHeight(20)
    frame.learn:SetPoint("TOPRIGHT", -10, -28)
    frame.learn:SetText("Learn")
    frame.learn:SetScript("OnClick", function() TA.LearnNext() end)

    frame.queue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.queue:SetPoint("TOPLEFT", 10, -60)
    frame.queue:SetPoint("RIGHT", -10, 0)
    frame.queue:SetJustifyH("LEFT")
    frame.queue:SetTextColor(0.7, 0.7, 0.7)

    frame.gearTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.gearTitle:SetPoint("TOPLEFT", frame.queue, "BOTTOMLEFT", 0, -8)
    frame.gearTitle:SetText("Gear upgrades in bags")

    frame.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(14)
        row:SetPoint("LEFT", 10, 0); row:SetPoint("RIGHT", -10, 0)
        if i == 1 then row:SetPoint("TOP", frame.gearTitle, "BOTTOM", 0, -3)
        else row:SetPoint("TOP", frame.rows[i - 1], "BOTTOM", 0, -1) end
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetAllPoints(); row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local u = self.upgrade
            if not u then return end
            if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(u.item.link) else TA.Equip(u) end
        end)
        row:SetScript("OnEnter", function(self)
            local u = self.upgrade
            if not u then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetBagItem(u.bag, u.slot)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Advisor score %.0f vs %.0f worn%s", u.score, u.wornScore,
                u.weaponSet and " (weapon set)" or ""), 0.4, 0.8, 1)
            GameTooltip:AddLine("Click to equip, shift-click to link.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.rows[i] = row
    end

    frame:Hide()
end

function TA.Render()
    if not frame then return end
    local db = DB()
    if db.pos then frame:ClearAllPoints(); frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end

    local a = state.analysis
    if not state.build then
        frame.icon:SetTexture(nil)
        frame.next:SetText("No levelling build for this class.")
        frame.sub:SetText(""); frame.queue:SetText(""); frame.learn:Hide()
    elseif not a or #a.unknown > 0 then
        frame.next:SetText("Build does not match the talent trees.")
        frame.sub:SetText(a and table.concat(a.unknown, " ") or ""); frame.queue:SetText(""); frame.learn:Hide()
    elseif #a.picks == 0 then
        frame.icon:SetTexture(nil)
        frame.next:SetText("Plan complete - " .. state.build.name)
        frame.sub:SetText(string.format("%d/%d points placed", a.spent, a.total))
        frame.queue:SetText(""); frame.learn:Hide()
    else
        local p = a.picks[1]
        local unspent = Unspent()
        frame.icon:SetTexture(p.talent.icon)
        frame.next:SetText(string.format("%s (%d/%d)", p.talent.name, p.rank, p.talent.maxRank))
        local where = string.format("%s, tier %d", state.talents.tabs[p.talent.tab] or "?", p.talent.tier)
        if p.blocked then
            frame.sub:SetText(string.format("%s - blocked: %d more point(s) in that tree first", where, p.need))
        elseif unspent > 0 then
            frame.sub:SetText(string.format("%s - %d point%s to spend", where, unspent, unspent == 1 and "" or "s"))
        else
            frame.sub:SetText(string.format("%s - next point at level %d", where, math.max(p.level, UnitLevel("player") + 1)))
        end
        local q = {}
        for i = 2, #a.picks do
            local n = a.picks[i]
            q[#q + 1] = string.format("%s %d/%d", n.talent.name, n.rank, n.talent.maxRank)
        end
        local off = ""
        if #a.offPlan > 0 then
            local names = {}
            for _, o in ipairs(a.offPlan) do names[#names + 1] = o.talent.name .. " +" .. o.extra end
            off = "\n|cffff8800Off plan:|r " .. table.concat(names, ", ")
        end
        frame.queue:SetText("Then: " .. (#q > 0 and table.concat(q, ", ") or "-") .. off)
        if unspent > 0 and not p.blocked then frame.learn:Show() else frame.learn:Hide() end
    end

    local n = 0
    for i, row in ipairs(frame.rows) do
        local u = state.upgrades[i]
        row.upgrade = u
        if u then
            n = n + 1
            local pct = u.wornScore > 0 and math.floor((u.score / u.wornScore - 1) * 100 + 0.5) or 100
            row.text:SetText(string.format("%s  |cff55ff55+%d%%|r%s", u.item.link, pct,
                u.weaponSet and (u.invSlot == 17 and " (off hand)" or " (main hand)") or ""))
            row:Show()
        else
            row.text:SetText(""); row:Hide()
        end
    end
    if n == 0 then frame.gearTitle:SetText("Gear upgrades in bags: none")
    else frame.gearTitle:SetText("Gear upgrades in bags") end

    local queueH = frame.queue:GetStringHeight() or 12
    frame:SetHeight(60 + queueH + 26 + n * 15 + 12)

    if db.shown and state.build then frame:Show() else frame:Hide() end
end

----------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------

local function OnLevelOrPoints()
    TA.RefreshTalents()
    state.dirtyGear = true -- level gates on gear may have opened
    TA.Render()
    local a = state.analysis
    if a and a.picks[1] and Unspent() > 0 then
        local p = a.picks[1]
        if DB().auto and not p.blocked and not InCombatLockdown() then
            TA.LearnNext()
        else
            Print(string.format("Next point: %s (%d/%d) in %s.", p.talent.name, p.rank, p.talent.maxRank,
                state.talents.tabs[p.talent.tab] or "?"))
        end
    end
end

local events = CreateFrame("Frame")

-- Bag scans are debounced here, on a frame that is never hidden: the advisor
-- frame may be closed, and the chat notice about a new upgrade still has to
-- come. An item the client has not cached yet marks the scan dirty again.
events.timer = 0
events:SetScript("OnUpdate", function(self, elapsed)
    if not state.dirtyGear then return end
    self.timer = self.timer + elapsed
    if self.timer < RESCAN_DELAY then return end
    state.dirtyGear = false; self.timer = 0
    state.pendingItems = false
    TA.RefreshGear(); TA.Render()
    if state.pendingItems then state.dirtyGear = true end
end)

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("CHARACTER_POINTS_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        BuildFrame()
        local ok, why = TA.SelectBuild()
        if not ok then Print(why .. " - only gear and talent frames for classes in Builds.lua."); TA.Render(); return end
        TA.RefreshTalents()
        state.dirtyGear = true
        TA.Render()
        local a = state.analysis
        if a and a.picks[1] then
            Print(string.format("%s - next: %s (%d/%d). /ta for options.", state.build.name,
                a.picks[1].talent.name, a.picks[1].rank, a.picks[1].talent.maxRank))
        end
    elseif event == "PLAYER_LEVEL_UP" or event == "CHARACTER_POINTS_CHANGED" then
        OnLevelOrPoints()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        TA.RefreshTalents(); state.dirtyGear = true; TA.Render()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then state.dirtyGear = true end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "SKILL_LINES_CHANGED" then
        state.dirtyGear = true
    end
end)

----------------------------------------------------------------------------
-- Slash
----------------------------------------------------------------------------

SLASH_TALENTADVISOR1 = "/ta"
SLASH_TALENTADVISOR2 = "/talentadvisor"
SlashCmdList.TALENTADVISOR = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    local db = DB()
    if cmd == "" or cmd == "toggle" then
        db.shown = not db.shown; TA.Render()
    elseif cmd == "show" then db.shown = true; TA.Render()
    elseif cmd == "hide" then db.shown = false; TA.Render()
    elseif cmd == "learn" then TA.LearnNext()
    elseif cmd == "auto" then
        if arg == "on" then db.auto = true elseif arg == "off" then db.auto = false end
        Print("Auto-learn on level up: " .. (db.auto and "on" or "off"))
    elseif cmd == "plan" then
        local a = state.analysis
        if not a then Print("No build."); return end
        Print(string.format("%s - %d/%d points. Remaining:", state.build.name, a.spent, a.total))
        local full = TA.Analyse(state.plan, state.talents, 200)
        local lvl, free = UnitLevel("player"), Unspent()
        for k, p in ipairs(full.picks) do
            local when = k <= free and "now " or string.format("L%-3d", lvl + k - free)
            Print(string.format("  %s %s %d/%d", when, p.talent.name, p.rank, p.talent.maxRank))
        end
        for _, o in ipairs(full.offPlan) do Print("  off plan: " .. o.talent.name .. " +" .. o.extra) end
    elseif cmd == "gear" or cmd == "scan" then
        state.announced = {}
        TA.RefreshGear(); TA.Render()
        if #state.upgrades == 0 then Print("Nothing in the bags beats what you wear.") end
    elseif cmd == "build" then
        if arg == "" then
            Print("Builds for this class: " .. table.concat(TA.BuildKeys(), ", ") .. " (current: " .. tostring(state.buildKey) .. ")")
        else
            local ok, why = TA.SelectBuild(arg)
            if ok then TA.RefreshTalents(); state.dirtyGear = true; TA.Render(); Print("Build: " .. state.build.name)
            else Print(why) end
        end
    elseif cmd == "margin" then
        local v = tonumber(arg)
        if v and v >= 0 and v < 100 then db.margin = 1 + v / 100; state.dirtyGear = true end
        Print(string.format("An item must beat the worn one by %d%% to be suggested.", math.floor((db.margin - 1) * 100 + 0.5)))
    elseif cmd == "weights" then
        if not state.build then Print("No build."); return end
        local parts = {}
        for k, v in pairs(state.build.weights) do parts[#parts + 1] = k .. "=" .. v end
        table.sort(parts)
        Print(table.concat(parts, "  "))
    elseif cmd == "notes" then
        if state.build and state.build.notes then for _, n in ipairs(state.build.notes) do Print(n) end end
    elseif cmd == "reset" then
        db.pos = nil; db.shown = true; TA.Render()
    else
        Print("/ta  toggle frame | show | hide | learn | auto on/off | plan | gear | build [name] | margin <pct> | weights | notes | reset")
    end
end
