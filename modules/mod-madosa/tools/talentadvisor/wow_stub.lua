-- Just enough of the WoW 3.3.5 client API for TalentAdvisor's Core.lua to
-- load under lua5.1. Frames are inert tables; anything called on them is a
-- no-op that returns nothing. The pure functions under test take plain data.

local function inert()
    local t = {}
    return setmetatable(t, { __index = function() return function() end end })
end

CreateFrame = function() return inert() end
UIParent = inert()
GameTooltip = inert()
SlashCmdList = {}
InCombatLockdown = function() return false end
_G = _G or getfenv(0)

CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }
