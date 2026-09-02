-- AdiBags_RecipeHint: an AdiBags plugin that answers, on the icon itself,
-- the one question a recipe in the bag raises - can I learn this?
--
--   green tick      this character can learn it right now
--   orange number   a profession this character has, but not at that skill yet
--   faint red cross already known
--   nothing         a profession this character does not have, or a recipe
--                   locked to another class or a higher level
--
-- There is no API that says "learnable"; the game tells you the way it tells
-- the player, in the tooltip: "Requires Tailoring (150)" drawn red when it is
-- not met, "Already known" when it is. So the plugin reads the tooltip off a
-- hidden GameTooltip, the same trick every "already known" bag addon uses.
-- Only the lines above the "Use:" line count as the recipe's own conditions:
-- what follows is the crafted item's tooltip, and its red "Requires Level 70"
-- is about the product, not the recipe.
--
-- It hangs off AdiBags' own plugin mechanism (AdiBags_UpdateButton, the same
-- message its Item level module listens to), so it shows up in AdiBags'
-- options as a module that can be switched off, and never touches a button
-- AdiBags is not drawing.

local addon = LibStub('AceAddon-3.0'):GetAddon('AdiBags', true)
if not addon then return end

local mod = addon:NewModule('RecipeHint', 'AceEvent-3.0')
mod.uiName = 'Recipe hint'
mod.uiDesc = 'Mark recipes you can learn (tick), need more skill for (number), or already know (cross).'

local _G = _G
local GetItemInfo = _G.GetItemInfo
local GetNumSkillLines = _G.GetNumSkillLines
local GetSkillLineInfo = _G.GetSkillLineInfo
local ExpandSkillHeader = _G.ExpandSkillHeader
local CollapseSkillHeader = _G.CollapseSkillHeader
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local pairs, tonumber, wipe, select = _G.pairs, _G.tonumber, _G.wipe, _G.select

-- Localised through the client's own strings, so the plugin reads any locale
-- the tooltip is written in.
local RECIPE_CLASS = select(9, _G.GetAuctionItemClasses())   -- "Recipe"
local KNOWN_TEXT = _G.ITEM_SPELL_KNOWN                          -- "Already known"
local USE_PREFIX = _G.ITEM_SPELL_TRIGGER_ONUSE                  -- "Use:"

-- "Requires %s (%d)" -> a Lua pattern capturing the profession and the rank.
local function ToPattern(format)
    local pattern = format:gsub('[%(%)%.%+%-%*%?%[%]%^%$]', '%%%0')
    pattern = pattern:gsub('%%s', '(.-)'):gsub('%%d', '(%%d+)')
    return '^' .. pattern .. '$'
end
local MIN_SKILL_PATTERN = ToPattern(_G.ITEM_MIN_SKILL)

local scanner = CreateFrame('GameTooltip', 'AdiBagsRecipeHintTooltip', UIParent, 'GameTooltipTemplate')
scanner:SetOwner(UIParent, 'ANCHOR_NONE')

-- name -> rank, for every skill line the character has. The skill window
-- only lists what is under an expanded header, so headers are opened for the
-- scan and closed again afterwards - from the bottom up, because collapsing
-- one shifts every index below it.
local professions = {}

local function ScanProfessions()
    wipe(professions)

    local collapsed = {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded then
            collapsed[name] = true
        end
    end

    ExpandSkillHeader(0)
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name and not isHeader then
            professions[name] = rank
        end
    end

    for i = GetNumSkillLines(), 1, -1 do
        local name, isHeader = GetSkillLineInfo(i)
        if isHeader and collapsed[name] then
            CollapseSkillHeader(i)
        end
    end
end

local function IsRed(fontString)
    local r, g, b = fontString:GetTextColor()
    return r > 0.9 and g < 0.3 and b < 0.3
end

-- Returns 'learnable', 'known', 'lowskill' (with the rank needed), or nil for
-- anything that is not a recipe or cannot be learned by this character at all.
local function Classify(bag, slot, itemId)
    local _, _, _, _, _, itemType = GetItemInfo(itemId)
    if itemType ~= RECIPE_CLASS then
        return nil
    end

    scanner:SetOwner(UIParent, 'ANCHOR_NONE')
    scanner:ClearLines()
    scanner:SetBagItem(bag, slot)

    local state, needed = 'learnable', nil
    local pastUseLine = false
    for i = 2, scanner:NumLines() do
        local line = _G['AdiBagsRecipeHintTooltipTextLeft' .. i]
        local text = line and line:GetText()
        if text then
            if text == KNOWN_TEXT then
                return 'known'
            end
            if text:sub(1, #USE_PREFIX) == USE_PREFIX then
                pastUseLine = true
            end
            if not pastUseLine then
                local profession, rank = text:match(MIN_SKILL_PATTERN)
                if profession then
                    if IsRed(line) then
                        if professions[profession] then
                            state, needed = 'lowskill', tonumber(rank)
                        else
                            return nil
                        end
                    end
                elseif IsRed(line) then
                    return nil   -- another class, a higher level: not this character's to learn
                end
            end
        end
    end
    return state, needed
end

-- One overlay per button, created on first use and reused; AdiBags recycles
-- its buttons, so the overlays follow whatever item the button shows next.
local overlays = {}

local function GetOverlay(button)
    local overlay = overlays[button]
    if overlay then
        return overlay
    end
    overlay = {}
    overlay.icon = button:CreateTexture(nil, 'OVERLAY')
    overlay.icon:SetSize(14, 14)
    overlay.icon:SetPoint('TOPRIGHT', button, 'TOPRIGHT', -1, -1)
    overlay.text = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    overlay.text:SetPoint('TOPRIGHT', button, 'TOPRIGHT', -2, -2)
    overlay.text:SetTextColor(1, 0.6, 0.1)
    overlays[button] = overlay
    return overlay
end

local function HideOverlay(button)
    local overlay = overlays[button]
    if overlay then
        overlay.icon:Hide()
        overlay.text:Hide()
    end
end

function mod:UpdateButton(event, button)
    local itemId = button:GetItemId()
    if not itemId then
        return HideOverlay(button)
    end

    local state, needed = Classify(button.bag, button.slot, itemId)
    if not state then
        return HideOverlay(button)
    end

    local overlay = GetOverlay(button)
    overlay.icon:Hide()
    overlay.text:Hide()
    if state == 'learnable' then
        overlay.icon:SetTexture('Interface\\RaidFrame\\ReadyCheck-Ready')
        overlay.icon:SetAlpha(1)
        overlay.icon:Show()
    elseif state == 'known' then
        overlay.icon:SetTexture('Interface\\RaidFrame\\ReadyCheck-NotReady')
        overlay.icon:SetAlpha(0.5)
        overlay.icon:Show()
    elseif state == 'lowskill' then
        overlay.text:SetText(needed or '')
        overlay.text:Show()
    end
end

function mod:Refresh()
    ScanProfessions()
    self:SendMessage('AdiBags_UpdateAllButtons')
end

function mod:OnEnable()
    ScanProfessions()
    self:RegisterMessage('AdiBags_UpdateButton', 'UpdateButton')
    -- A profession gained or raised, or a recipe just learned, changes the
    -- answer for every recipe in the bag.
    self:RegisterEvent('SKILL_LINES_CHANGED', 'Refresh')
    self:RegisterEvent('LEARNED_SPELL_IN_TAB', 'Refresh')
    self:SendMessage('AdiBags_UpdateAllButtons')
end

function mod:OnDisable()
    for button in pairs(overlays) do
        HideOverlay(button)
    end
end
