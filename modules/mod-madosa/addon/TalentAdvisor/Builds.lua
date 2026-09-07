-- TalentAdvisor builds: the data Core.lua advises from.
--
-- A build is an ordered list of steps. Each step names a talent by its place
-- in the tree - tab index, tier, column, all 1-based exactly as
-- GetTalentInfo() reports them - and how many points go there before the plan
-- moves on. The same talent may appear more than once (Improved Shields gets
-- two points early and its third much later), which is what lets a plan say
-- "come back to this" instead of forcing every talent to be filled in one go.
--
-- Position is used instead of names on purpose: names are localised, tiers
-- and columns are not, so a plan written here works on any client language.
-- The names Core.lua shows are read live from the game.
--
-- The tab order is the order the trees appear in the talent window
-- (TalentTab.dbc OrderIndex): Shaman 1 = Elemental, 2 = Enhancement,
-- 3 = Restoration.
--
-- weights: how many "points" one unit of a stat is worth when ranking gear,
-- with attack power fixed at 1. Weapon damage is rated per DPS and per hand
-- (DPS_MH, DPS_OH, DPS_2H), and slow weapons get SPEED_MH / SPEED_2H per
-- second of speed above 2.0. These are levelling heuristics tuned to the
-- build below, not raid-sim output; /ta weights lists them.

TalentAdvisorBuilds = {
    SHAMAN = {
        default = "enhancement",

        enhancement = {
            name = "Enhancement (levelling)",
            -- The talent that turns on dual wielding. Gear advice compares
            -- two one-handers against one two-hander only once it is known.
            dualWield = { tab = 2, tier = 7, col = 2 },

            -- {tab, tier, col, points}. Levels 10-80, 71 points.
            steps = {
                { 2,  1, 3, 5 }, -- 10-14 Ancestral Knowledge
                { 2,  2, 3, 2 }, -- 15-16 Improved Ghost Wolf
                { 2,  2, 2, 5 }, -- 17-21 Thundering Strikes
                { 2,  3, 3, 1 }, -- 22    Shamanistic Focus
                { 2,  2, 4, 2 }, -- 23-24 Improved Shields 2/3
                { 2,  4, 2, 5 }, -- 25-29 Flurry
                { 2,  3, 1, 3 }, -- 30-32 Elemental Weapons
                { 2,  5, 2, 1 }, -- 33    Spirit Weapons
                { 2,  2, 4, 1 }, -- 34    Improved Shields 3/3
                { 2,  5, 3, 3 }, -- 35-37 Mental Dexterity
                { 2,  6, 3, 2 }, -- 38-39 Weapon Mastery 2/3
                { 2,  7, 2, 1 }, -- 40    Dual Wield
                { 2,  7, 3, 1 }, -- 41    Stormstrike
                { 2,  6, 3, 1 }, -- 42    Weapon Mastery 3/3
                { 2,  7, 1, 3 }, -- 43-45 Dual Wield Specialization
                { 2,  8, 2, 1 }, -- 46    Lava Lash
                { 2,  8, 3, 2 }, -- 47-48 Improved Stormstrike
                { 2,  8, 1, 1 }, -- 49    Static Shock 1/3
                { 2,  9, 2, 1 }, -- 50    Shamanistic Rage
                { 2,  9, 1, 3 }, -- 51-53 Mental Quickness
                { 2,  8, 1, 1 }, -- 54    Static Shock 2/3
                { 2, 10, 2, 5 }, -- 55-59 Maelstrom Weapon
                { 2, 11, 2, 1 }, -- 60    Feral Spirit
                { 2,  6, 1, 3 }, -- 61-63 Unleashed Rage
                { 2,  4, 3, 5 }, -- 64-68 Toughness
                { 2,  8, 1, 1 }, -- 69    Static Shock 3/3
                { 2,  5, 1, 2 }, -- 70-71 Improved Windfury Totem
                { 1,  1, 3, 5 }, -- 72-76 Concussion
                { 1,  2, 3, 3 }, -- 77-79 Elemental Devastation
                { 1,  2, 1, 1 }, -- 80    Call of Flame
            },

            weights = {
                STR = 2.2, AGI = 2.0, INT = 1.1, STA = 0.7, SPI = 0.1,
                AP = 1.0, CRIT = 1.9, HIT = 2.2, HASTE = 1.3, EXP = 1.8,
                ARP = 1.0, SP = 0.35, MP5 = 0.6, ARMOR = 0.03, BLOCK = 0.1,
                DPS_MH = 5.5, DPS_OH = 3.0, DPS_2H = 5.5,
                SPEED_MH = 25, SPEED_2H = 25,
            },

            notes = {
                "Imbue: Rockbiter -> Flametongue at 10 -> Windfury at 30 on the main hand. From 40 Windfury MH + Flametongue OH (Lava Lash).",
                "Shield: Lightning Shield until 20, Water Shield after.",
                "Weapons: the slowest two-hander you can find until 40, two slow one-handers after.",
            },
        },
    },
}
