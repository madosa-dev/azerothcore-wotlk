-- lua5.1 run_tests.lua   (from this directory, or give the addon dir as arg 1)
--
-- Plays the shipped builds through the real talent trees - tiers, columns,
-- max ranks and prerequisites as they are in Talent.dbc - and checks the gear
-- scoring on constructed items. No client needed.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local addon = arg[1] or (here .. "/../../addon/TalentAdvisor")
dofile(here .. "/wow_stub.lua")
dofile(addon .. "/Builds.lua")
dofile(addon .. "/Core.lua")
local TA = TalentAdvisor

-- Shaman trees from Talent.dbc: tab (window order), tier, column, max rank,
-- name; prereq = {tab, tier, col, rank} where the tree has one.
local SHAMAN = {
    { 1, 1, 2, 5, "Convection" }, { 1, 1, 3, 5, "Concussion" }, { 1, 2, 1, 3, "Call of Flame" },
    { 1, 2, 2, 3, "Elemental Warding" }, { 1, 2, 3, 3, "Elemental Devastation" }, { 1, 3, 1, 5, "Reverberation" },
    { 1, 3, 2, 1, "Elemental Focus" }, { 1, 3, 3, 5, "Elemental Fury" }, { 1, 4, 1, 2, "Improved Fire Nova" },
    { 1, 4, 4, 3, "Eye of the Storm" }, { 1, 5, 1, 2, "Elemental Reach" },
    { 1, 5, 2, 1, "Call of Thunder", prereq = { 1, 3, 2, 1 } }, { 1, 5, 4, 3, "Unrelenting Storm" },
    { 1, 6, 1, 3, "Elemental Precision" }, { 1, 6, 3, 5, "Lightning Mastery", prereq = { 1, 3, 3, 5 } },
    { 1, 7, 2, 1, "Elemental Mastery", prereq = { 1, 5, 2, 1 } }, { 1, 7, 3, 3, "Storm, Earth and Fire" },
    { 1, 8, 1, 2, "Booming Echoes" }, { 1, 8, 2, 2, "Elemental Oath", prereq = { 1, 7, 2, 1 } },
    { 1, 8, 3, 3, "Lightning Overload" }, { 1, 9, 1, 3, "Astral Shift" }, { 1, 9, 2, 1, "Totem of Wrath" },
    { 1, 9, 3, 3, "Lava Flows" }, { 1, 10, 2, 5, "Shamanism" }, { 1, 11, 2, 1, "Thunderstorm" },

    { 2, 1, 1, 3, "Enhancing Totems" }, { 2, 1, 2, 2, "Earth's Grasp" }, { 2, 1, 3, 5, "Ancestral Knowledge" },
    { 2, 2, 1, 2, "Guardian Totems" }, { 2, 2, 2, 5, "Thundering Strikes" }, { 2, 2, 3, 2, "Improved Ghost Wolf" },
    { 2, 2, 4, 3, "Improved Shields" }, { 2, 3, 1, 3, "Elemental Weapons" }, { 2, 3, 3, 1, "Shamanistic Focus" },
    { 2, 3, 4, 3, "Anticipation" }, { 2, 4, 2, 5, "Flurry", prereq = { 2, 2, 2, 5 } }, { 2, 4, 3, 5, "Toughness" },
    { 2, 5, 1, 2, "Improved Windfury Totem" }, { 2, 5, 2, 1, "Spirit Weapons" }, { 2, 5, 3, 3, "Mental Dexterity" },
    { 2, 6, 1, 3, "Unleashed Rage" }, { 2, 6, 3, 3, "Weapon Mastery" }, { 2, 6, 4, 2, "Frozen Power" },
    { 2, 7, 1, 3, "Dual Wield Specialization", prereq = { 2, 7, 2, 1 } },
    { 2, 7, 2, 1, "Dual Wield", prereq = { 2, 5, 2, 1 } }, { 2, 7, 3, 1, "Stormstrike" },
    { 2, 8, 1, 3, "Static Shock" }, { 2, 8, 2, 1, "Lava Lash", prereq = { 2, 7, 2, 1 } },
    { 2, 8, 3, 2, "Improved Stormstrike", prereq = { 2, 7, 3, 1 } }, { 2, 9, 1, 3, "Mental Quickness" },
    { 2, 9, 2, 1, "Shamanistic Rage" }, { 2, 9, 3, 2, "Earthen Power" }, { 2, 10, 2, 5, "Maelstrom Weapon" },
    { 2, 11, 2, 1, "Feral Spirit" },

    { 3, 1, 2, 5, "Improved Healing Wave" }, { 3, 1, 3, 5, "Totemic Focus" }, { 3, 2, 1, 2, "Improved Reincarnation" },
    { 3, 2, 2, 3, "Healing Grace" }, { 3, 2, 3, 5, "Tidal Focus" }, { 3, 3, 1, 3, "Improved Water Shield" },
    { 3, 3, 2, 3, "Healing Focus" }, { 3, 3, 3, 1, "Tidal Force" }, { 3, 3, 4, 3, "Ancestral Healing" },
    { 3, 4, 2, 3, "Restorative Totems" }, { 3, 4, 3, 5, "Tidal Mastery" }, { 3, 5, 1, 3, "Healing Way" },
    { 3, 5, 3, 1, "Nature's Swiftness" }, { 3, 5, 4, 3, "Focused Mind" }, { 3, 6, 3, 5, "Purification" },
    { 3, 7, 1, 5, "Nature's Guardian" }, { 3, 7, 2, 1, "Mana Tide Totem", prereq = { 3, 4, 2, 3 } },
    { 3, 7, 3, 1, "Cleanse Spirit", prereq = { 3, 6, 3, 5 } }, { 3, 8, 1, 2, "Blessing of the Eternals" },
    { 3, 8, 2, 2, "Improved Chain Heal" }, { 3, 8, 3, 3, "Nature's Blessing" }, { 3, 9, 1, 3, "Ancestral Awakening" },
    { 3, 9, 2, 1, "Earth Shield" }, { 3, 9, 3, 2, "Improved Earth Shield", prereq = { 3, 9, 2, 1 } },
    { 3, 10, 2, 5, "Tidal Waves" }, { 3, 11, 2, 1, "Riptide" },
}

local TREES = { SHAMAN = SHAMAN }

-- A fresh talent snapshot in the shape TA.ReadTalents() returns.
local function Snapshot(tree)
    local t = { byKey = {}, points = { [1] = 0, [2] = 0, [3] = 0 }, tabs = { "Tab1", "Tab2", "Tab3" } }
    for i, row in ipairs(tree) do
        t.byKey[TA.Key(row[1], row[2], row[3])] = {
            name = row[5], icon = "", tier = row[2], col = row[3], rank = 0, maxRank = row[4],
            tab = row[1], index = i, prereq = row.prereq,
        }
    end
    return t
end

-- Put a point in, the way the game would allow it. Errors describe why not.
local function Learn(t, key)
    local tal = assert(t.byKey[key], "no talent " .. key)
    assert(tal.rank < tal.maxRank, tal.name .. " is already " .. tal.rank .. "/" .. tal.maxRank)
    assert(t.points[tal.tab] >= 5 * (tal.tier - 1),
        string.format("%s: tier %d needs %d points in tab %d, have %d", tal.name, tal.tier, 5 * (tal.tier - 1), tal.tab, t.points[tal.tab]))
    if tal.prereq then
        local p = t.byKey[TA.Key(tal.prereq[1], tal.prereq[2], tal.prereq[3])]
        assert(p.rank >= tal.prereq[4], string.format("%s needs %s %d/%d", tal.name, p.name, tal.prereq[4], p.maxRank))
    end
    tal.rank = tal.rank + 1
    t.points[tal.tab] = t.points[tal.tab] + 1
end

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("  ok   " .. name)
    else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

print("TalentAdvisor tests")

-- Every shipped build, against its class tree ------------------------------
for class, set in pairs(TalentAdvisorBuilds) do
    local tree = assert(TREES[class], "no test tree for " .. class)
    for key, build in pairs(set) do
        if type(build) == "table" and build.steps then
            local plan = TA.ExpandPlan(build)
            test(class .. "/" .. key .. ": 71 points, one per level 10-80", function()
                eq(#plan, 71, "plan length")
            end)
            test(class .. "/" .. key .. ": every talent exists", function()
                local t = Snapshot(tree)
                local a = TA.Analyse(plan, t, 1)
                eq(#a.unknown, 0, "unknown steps " .. table.concat(a.unknown, " "))
            end)
            test(class .. "/" .. key .. ": playable in order (tiers, ranks, prerequisites)", function()
                local t = Snapshot(tree)
                for i = 1, #plan do
                    local a = TA.Analyse(plan, t, 1)
                    local p = a.picks[1]
                    assert(p, "no pick at step " .. i)
                    eq(p.planIndex, i, "pick index at step " .. i)
                    eq(p.level, 9 + i, "level at step " .. i)
                    assert(not p.blocked, p.talent.name .. " blocked at step " .. i)
                    Learn(t, p.key)
                end
                local a = TA.Analyse(plan, t, 1)
                eq(#a.picks, 0, "picks left"); eq(#a.offPlan, 0, "off plan"); eq(a.spent, 71, "spent")
            end)
            test(class .. "/" .. key .. ": dualWield step is in the plan", function()
                local d = build.dualWield
                local found = false
                for _, s in ipairs(plan) do if s.tab == d.tab and s.tier == d.tier and s.col == d.col then found = true end end
                assert(found, "dual wield talent not in plan")
            end)
        end
    end
end

-- Named spot checks: the coordinates in Builds.lua mean what the comments say
local ENH_AT_LEVEL = {
    [10] = "Ancestral Knowledge", [15] = "Improved Ghost Wolf", [17] = "Thundering Strikes",
    [22] = "Shamanistic Focus", [23] = "Improved Shields", [25] = "Flurry", [30] = "Elemental Weapons",
    [33] = "Spirit Weapons", [34] = "Improved Shields", [35] = "Mental Dexterity", [38] = "Weapon Mastery",
    [40] = "Dual Wield", [41] = "Stormstrike", [43] = "Dual Wield Specialization", [46] = "Lava Lash",
    [47] = "Improved Stormstrike", [49] = "Static Shock", [50] = "Shamanistic Rage", [51] = "Mental Quickness",
    [55] = "Maelstrom Weapon", [60] = "Feral Spirit", [61] = "Unleashed Rage", [64] = "Toughness",
    [70] = "Improved Windfury Totem", [72] = "Concussion", [77] = "Elemental Devastation", [80] = "Call of Flame",
}
test("SHAMAN/enhancement: the talent at each level is the one the plan promises", function()
    local t = Snapshot(SHAMAN)
    local p = TA.ExpandPlan(TalentAdvisorBuilds.SHAMAN.enhancement)
    local counts = {}
    for i, step in ipairs(p) do
        local tal = t.byKey[TA.Key(step.tab, step.tier, step.col)]
        local want = ENH_AT_LEVEL[9 + i]
        if want then eq(tal.name, want, "level " .. (9 + i)) end
        counts[tal.name] = (counts[tal.name] or 0) + 1
    end
    eq(counts["Improved Shields"], 3, "Improved Shields total")
    eq(counts["Anticipation"], nil, "Anticipation must not be in the plan")
    eq(counts["Static Shock"], 3, "Static Shock total")
end)

-- The walk under deviations -----------------------------------------------
local enh = TalentAdvisorBuilds.SHAMAN.enhancement
local plan = TA.ExpandPlan(enh)

test("fresh character: first pick is Ancestral Knowledge 1/5 at level 10", function()
    local a = TA.Analyse(plan, Snapshot(SHAMAN), 4)
    eq(a.picks[1].talent.name, "Ancestral Knowledge"); eq(a.picks[1].rank, 1); eq(a.picks[1].level, 10)
    eq(#a.picks, 4, "queue length")
end)

test("points saved up: queue simulates its own tier gates", function()
    local t = Snapshot(SHAMAN)
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end          -- AK 5/5
    for _ = 1, 2 do Learn(t, TA.Key(2, 2, 3)) end          -- Imp Ghost Wolf 2/2
    for _ = 1, 5 do Learn(t, TA.Key(2, 2, 2)) end          -- TS 5/5 -> 12 points
    local a = TA.Analyse(plan, t, 10)
    -- next: SF, IS, IS (15) then Flurry x5 (tier 4 opens at 15 via the queue itself)
    eq(a.picks[1].talent.name, "Shamanistic Focus")
    eq(a.picks[4].talent.name, "Flurry"); assert(not a.picks[4].blocked, "Flurry should be open once queue reaches 15")
end)

test("off-plan points are reported and do not shift the plan", function()
    local t = Snapshot(SHAMAN)
    for _ = 1, 5 do Learn(t, TA.Key(3, 1, 3)) end          -- Totemic Focus 5/5 (Resto)
    local a = TA.Analyse(plan, t, 2)
    eq(#a.offPlan, 1, "off plan entries"); eq(a.offPlan[1].talent.name, "Totemic Focus"); eq(a.offPlan[1].extra, 5)
    eq(a.picks[1].talent.name, "Ancestral Knowledge"); eq(a.spent, 5)
end)

test("a talent filled beyond the plan is off-plan only for the extra ranks", function()
    local t = Snapshot(SHAMAN)
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end
    for _ = 1, 3 do Learn(t, TA.Key(2, 2, 4)) end          -- Improved Shields 3/3 early (plan: 2 now, 1 later)
    local a = TA.Analyse(plan, t, 3)
    eq(#a.offPlan, 0, "3/3 is the plan total, nothing extra")
    eq(a.picks[1].talent.name, "Improved Ghost Wolf")
    -- the later "Improved Shields 3/3" step must be satisfied already, never re-suggested
    local full = TA.Analyse(plan, t, 200)
    for _, p in ipairs(full.picks) do assert(p.talent.name ~= "Improved Shields", "Improved Shields re-suggested") end
end)

test("blocked pick names the missing points", function()
    local t = Snapshot(SHAMAN)
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end
    for _ = 1, 2 do Learn(t, TA.Key(2, 2, 3)) end
    for _ = 1, 5 do Learn(t, TA.Key(2, 2, 2)) end
    Learn(t, TA.Key(2, 3, 3)); Learn(t, TA.Key(2, 2, 4)); Learn(t, TA.Key(2, 2, 4))   -- 15
    t.points[2] = 12                                          -- pretend three of those were refunded
    local a = TA.Analyse(plan, t, 1)
    eq(a.picks[1].talent.name, "Flurry"); assert(a.picks[1].blocked, "should be blocked"); eq(a.picks[1].need, 3)
end)

-- Gear scoring ----------------------------------------------------------------
local W = enh.weights
local function item(id, loc, stats, speed, usable)
    return { id = id, link = "[" .. id .. "]", name = tostring(id), equipLoc = loc, stats = stats or {},
        speed = speed, usable = usable ~= false, minLevel = 1 }
end

test("stat weights: AP is 1, strength counts double-ish", function()
    eq(TA.Score(item(1, "INVTYPE_CHEST", { AP = 10 }), W), 10)
    assert(TA.Score(item(1, "INVTYPE_CHEST", { STR = 10 }), W) > 20)
end)

test("weapon: DPS and speed only count when a hand is given", function()
    local w = item(1, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.4)
    eq(TA.Score(w, W), 0)
    eq(TA.Score(w, W, "2H"), 20 * W.DPS_2H + 1.4 * W.SPEED_2H)
end)

test("slot upgrade with margin; equal-ish items are not suggested", function()
    local worn = { [5] = item(10, "INVTYPE_CHEST", { STA = 10, AGI = 10 }) }
    local better = item(11, "INVTYPE_CHEST", { STA = 10, AGI = 14 })
    local same = item(12, "INVTYPE_CHEST", { STA = 10, AGI = 10 })
    local ups = TA.FindUpgrades({ { item = better, bag = 0, slot = 1 }, { item = same, bag = 0, slot = 2 } }, worn, W, false)
    eq(#ups, 1); eq(ups[1].item.id, 11); eq(ups[1].invSlot, 5)
end)

test("unusable (red tooltip line) and already-worn ids are skipped", function()
    local worn = { [11] = item(20, "INVTYPE_FINGER", { AP = 10 }) }
    local red = item(21, "INVTYPE_FINGER", { AP = 100 }, nil, false)
    local dup = item(20, "INVTYPE_FINGER", { AP = 10 })
    eq(#TA.FindUpgrades({ { item = red, bag = 0, slot = 1 }, { item = dup, bag = 0, slot = 2 } }, worn, W, false), 0)
end)

test("rings and trinkets replace the weaker of their two slots", function()
    local worn = { [11] = item(30, "INVTYPE_FINGER", { AP = 30 }), [12] = item(31, "INVTYPE_FINGER", { AP = 10 }) }
    local ring = item(32, "INVTYPE_FINGER", { AP = 20 })
    local ups = TA.FindUpgrades({ { item = ring, bag = 0, slot = 1 } }, worn, W, false)
    eq(#ups, 1); eq(ups[1].invSlot, 12)
end)

test("before dual wield: a slow two-hander beats a one-hander, a one-hander is not an off hand", function()
    local worn = { [16] = item(40, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.3) }
    local twoH = item(41, "INVTYPE_2HWEAPON", { DPS = 24 }, 3.5)
    local oneH = item(42, "INVTYPE_WEAPON", { DPS = 22 }, 2.6)
    local ups = TA.FindUpgrades({ { item = twoH, bag = 0, slot = 1 }, { item = oneH, bag = 0, slot = 2 } }, worn, W, false)
    eq(#ups, 1); eq(ups[1].item.id, 41); eq(ups[1].invSlot, 16); assert(ups[1].weaponSet)
end)

test("with dual wield: a one-hander goes to the empty off hand next to the main hand", function()
    local worn = { [16] = item(50, "INVTYPE_WEAPON", { DPS = 30 }, 2.6) }
    local oneH = item(51, "INVTYPE_WEAPON", { DPS = 25 }, 2.5)
    local ups = TA.FindUpgrades({ { item = oneH, bag = 0, slot = 1 } }, worn, W, true)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
end)

test("with dual wield: a two-hander must beat both hands together", function()
    local worn = { [16] = item(60, "INVTYPE_WEAPON", { DPS = 30 }, 2.6), [17] = item(61, "INVTYPE_WEAPON", { DPS = 28 }, 2.4) }
    local twoH = item(62, "INVTYPE_2HWEAPON", { DPS = 40 }, 3.4)
    eq(#TA.FindUpgrades({ { item = twoH, bag = 0, slot = 1 } }, worn, W, true), 0)
    local huge = item(63, "INVTYPE_2HWEAPON", { DPS = 60, STR = 30 }, 3.6)
    local ups = TA.FindUpgrades({ { item = huge, bag = 0, slot = 1 } }, worn, W, true)
    eq(#ups, 1); eq(ups[1].invSlot, 16)
end)

test("a better one-hander replaces the weaker hand, not the stronger", function()
    local worn = { [16] = item(70, "INVTYPE_WEAPON", { DPS = 30 }, 2.6), [17] = item(71, "INVTYPE_WEAPON", { DPS = 15 }, 1.8) }
    local oneH = item(72, "INVTYPE_WEAPON", { DPS = 26 }, 2.5)
    local ups = TA.FindUpgrades({ { item = oneH, bag = 0, slot = 1 } }, worn, W, true)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
end)

test("shield goes to the off hand while a one-hander is worn, never next to a two-hander", function()
    local shield = item(80, "INVTYPE_SHIELD", { STA = 20, ARMOR = 500 })
    local ups = TA.FindUpgrades({ { item = shield, bag = 0, slot = 1 } }, { [16] = item(81, "INVTYPE_WEAPON", { DPS = 20 }, 2.5) }, W, false)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
    eq(#TA.FindUpgrades({ { item = shield, bag = 0, slot = 1 } }, { [16] = item(82, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.3) }, W, false), 0)
end)

test("upgrades are sorted by gain", function()
    local worn = { [1] = item(90, "INVTYPE_HEAD", { AP = 10 }), [8] = item(91, "INVTYPE_FEET", { AP = 10 }) }
    local small = item(92, "INVTYPE_HEAD", { AP = 15 })
    local big = item(93, "INVTYPE_FEET", { AP = 40 })
    local ups = TA.FindUpgrades({ { item = small, bag = 0, slot = 1 }, { item = big, bag = 0, slot = 2 } }, worn, W, false)
    eq(ups[1].item.id, 93); eq(ups[2].item.id, 92)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
