-- lua5.1 run_tests.lua   (from this directory, or give the addon dir as arg 1)
--
-- Plays every shipped build through the real talent trees - tiers, columns,
-- max ranks and prerequisites straight out of Talent.dbc via dump_trees.py -
-- and checks the gear scoring on constructed items. No client needed.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local addon = arg[1] or (here .. "/../../addon/TalentAdvisor")
dofile(here .. "/wow_stub.lua")
dofile(here .. "/../wowsim/data/talents.lua")
dofile(addon .. "/Builds.lua")
dofile(addon .. "/Core.lua")
local TA = TalentAdvisor

local POINTS = 71

-- A fresh talent snapshot in the shape TA.ReadTalents() returns, built from
-- the generated tree for one class.
local function Snapshot(class)
    local tree = assert(TalentTrees[class], "no tree for " .. class)
    local t = { byKey = {}, points = {}, tabs = {} }
    for tab = 1, 3 do
        local data = assert(tree[tab], class .. " has no tab " .. tab)
        t.tabs[tab] = data.name
        t.points[tab] = 0
        for i, row in ipairs(data.talents) do
            t.byKey[TA.Key(tab, row[1], row[2])] = {
                name = row[4], icon = "", tier = row[1], col = row[2], rank = 0,
                maxRank = row[3], tab = tab, index = i, prereq = row.prereq,
            }
        end
    end
    return t
end

-- Put a point in, the way the game would allow it. Errors describe why not.
local function Learn(t, key)
    local tal = assert(t.byKey[key], "no talent " .. key)
    assert(tal.rank < tal.maxRank, tal.name .. " is already " .. tal.rank .. "/" .. tal.maxRank)
    assert(t.points[tal.tab] >= 5 * (tal.tier - 1),
        string.format("%s: tier %d needs %d points in tab %d, have %d", tal.name, tal.tier,
            5 * (tal.tier - 1), tal.tab, t.points[tal.tab]))
    if tal.prereq then
        local p = t.byKey[TA.Key(tal.prereq[1], tal.prereq[2], tal.prereq[3])]
        assert(p and p.rank >= tal.prereq[4],
            string.format("%s needs %s %d/%d", tal.name, p and p.name or "?", tal.prereq[4],
                p and p.maxRank or 0))
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
local function eq(a, b, what)
    if a ~= b then
        error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
    end
end

local function sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

print("TalentAdvisor tests")

----------------------------------------------------------------------------
-- Every shipped build, against its class tree
----------------------------------------------------------------------------

local ROLES = { melee = true, caster = true, heal = true, tank = true }

for _, class in ipairs(sortedKeys(TalentAdvisorBuilds)) do
    local set = TalentAdvisorBuilds[class]
    assert(TalentTrees[class], "no tree for " .. class)

    test(class .. ": default names a build that exists", function()
        local d = set.default
        assert(type(d) == "string", "no default")
        assert(type(set[d]) == "table" and set[d].steps, "default '" .. tostring(d) .. "' is not a build")
    end)

    for _, key in ipairs(sortedKeys(set)) do
        local build = set[key]
        if type(build) == "table" and build.steps then
            local id = class .. "/" .. key
            local plan = TA.ExpandPlan(build)

            test(id .. ": " .. POINTS .. " points, one per level 10-80", function()
                eq(#plan, POINTS, "plan length")
            end)

            test(id .. ": every talent exists in the class tree", function()
                local a = TA.Analyse(plan, Snapshot(class), 1)
                eq(#a.unknown, 0, "unknown steps " .. table.concat(a.unknown, " "))
            end)

            test(id .. ": playable in order (tiers, ranks, prerequisites)", function()
                local t = Snapshot(class)
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
                eq(#a.picks, 0, "picks left"); eq(#a.offPlan, 0, "off plan"); eq(a.spent, POINTS, "spent")
            end)

            test(id .. ": the spent header matches where the points land", function()
                local spent = { 0, 0, 0 }
                for _, step in ipairs(plan) do spent[step.tab] = spent[step.tab] + 1 end
                for tab = 1, 3 do eq(spent[tab], build.spent[tab], "tab " .. tab) end
            end)

            test(id .. ": describes itself (role, school, weights, notes)", function()
                assert(ROLES[build.role], "bad role " .. tostring(build.role))
                assert(build.school == "melee" or build.school == "spell", "bad school")
                assert(type(build.desc) == "string" and #build.desc > 0, "no desc")
                assert(type(build.notes) == "table" and #build.notes > 0, "no notes")
                for _, stat in ipairs({ "STR", "AGI", "STA", "INT", "SPI", "AP", "SP", "CRIT",
                    "HIT", "HASTE", "EXP", "ARP", "MP5", "ARMOR", "DEF", "DODGE", "PARRY",
                    "BLOCK", "BLOCKR", "RESIL", "DPS_MH", "DPS_OH", "DPS_2H" }) do
                    assert(type(build.weights[stat]) == "number", "no weight for " .. stat)
                end
                assert(type(build.armorFloor) == "number", "no armour floor")
            end)

            test(id .. ": dual wield is declared in a form the addon understands", function()
                local d = build.dualWield
                if d == nil then return end
                if d == true then return end
                assert(type(d) == "table", "dualWield must be true, a level or a talent")
                if d.level then
                    assert(d.level >= 10 and d.level <= 80, "odd dual wield level")
                    return
                end
                local t = Snapshot(class)
                assert(t.byKey[TA.Key(d.tab, d.tier, d.col)], "dual wield talent is not in the tree")
                local found = false
                for _, s in ipairs(plan) do
                    if s.tab == d.tab and s.tier == d.tier and s.col == d.col then found = true end
                end
                assert(found, "dual wield talent is not in the plan")
            end)

            if build.shield then
                test(id .. ": a shield build is never offered a two-hander", function()
                    local worn = { [16] = { id = 1, equipLoc = "INVTYPE_WEAPON", stats = { DPS = 10 }, speed = 2.5, usable = true } }
                    local twoH = { id = 2, link = "[2]", equipLoc = "INVTYPE_2HWEAPON",
                        stats = { DPS = 999, STR = 999, SP = 999, STA = 999 }, speed = 3.6, usable = true }
                    eq(TA.CompareWeapon(twoH, worn, build, false), nil, "two-hander accepted")
                    eq(#TA.FindUpgrades({ { item = twoH, bag = 0, slot = 1 } }, worn, build, false), 0)
                end)
            end
        end
    end
end

----------------------------------------------------------------------------
-- Roles and the picker's grouping
----------------------------------------------------------------------------

test("every class offers a melee or caster build and at least three builds", function()
    for _, class in ipairs(sortedKeys(TalentAdvisorBuilds)) do
        local groups = TA.BuildsByRole(class)
        local n, roles = 0, {}
        for _, g in ipairs(groups) do
            roles[g.role] = true
            n = n + #g.builds
        end
        assert(n >= 3, class .. " has only " .. n .. " builds")
        assert(roles.melee or roles.caster, class .. " has no damage build")
    end
end)

test("picker groups follow the role order and put meta builds last", function()
    local groups = TA.BuildsByRole("SHAMAN")
    local order = {}
    for _, g in ipairs(groups) do order[#order + 1] = g.role end
    eq(table.concat(order, ","), "melee,caster,heal,tank", "role order")
    for _, g in ipairs(groups) do
        local seenMeta = false
        for _, e in ipairs(g.builds) do
            if e.build.meta then seenMeta = true
            else assert(not seenMeta, "a plain build follows a meta one in " .. g.role) end
        end
    end
end)

test("the off-beat builds are the ones marked meta", function()
    local meta = {}
    for _, class in ipairs(sortedKeys(TalentAdvisorBuilds)) do
        for _, g in ipairs(TA.BuildsByRole(class)) do
            for _, e in ipairs(g.builds) do
                if e.build.meta then meta[#meta + 1] = class .. "/" .. e.key end
            end
        end
    end
    table.sort(meta)
    eq(table.concat(meta, " "),
       "PALADIN/shockadin ROGUE/riposte SHAMAN/tank WARRIOR/gladiator", "meta builds")
end)

----------------------------------------------------------------------------
-- Named spot checks on the shaman enhancement plan
----------------------------------------------------------------------------

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
    local t = Snapshot("SHAMAN")
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

test("the capstones land where the tree gates them", function()
    local want = {
        { "SHAMAN", "enhancement", "Feral Spirit", 60 },
        { "SHAMAN", "elemental", "Thunderstorm", 66 },
        { "SHAMAN", "restoration", "Riptide", 73 },
        { "WARRIOR", "arms", "Mortal Strike", 40 },
        { "WARRIOR", "fury", "Titan's Grip", 66 },
        { "WARRIOR", "protection", "Shockwave", 61 },
        { "PALADIN", "retribution", "Crusader Strike", 57 },
        { "PALADIN", "holy", "Holy Shock", 45 },
        { "PALADIN", "protection", "Hammer of the Righteous", 63 },
        { "ROGUE", "combat", "Killing Spree", 60 },
        { "ROGUE", "assassination", "Mutilate", 54 },
        { "ROGUE", "subtlety", "Shadow Dance", 63 },
    }
    for _, row in ipairs(want) do
        local class, key, name, level = row[1], row[2], row[3], row[4]
        local t = Snapshot(class)
        local plan = TA.ExpandPlan(TalentAdvisorBuilds[class][key])
        local at
        for i, step in ipairs(plan) do
            local tal = t.byKey[TA.Key(step.tab, step.tier, step.col)]
            if tal.name == name and not at then at = 9 + i end
        end
        eq(at, level, class .. "/" .. key .. " " .. name)
    end
end)

----------------------------------------------------------------------------
-- The walk under deviations
----------------------------------------------------------------------------

local enh = TalentAdvisorBuilds.SHAMAN.enhancement
local plan = TA.ExpandPlan(enh)

test("fresh character: first pick is Ancestral Knowledge 1/5 at level 10", function()
    local a = TA.Analyse(plan, Snapshot("SHAMAN"), 4)
    eq(a.picks[1].talent.name, "Ancestral Knowledge"); eq(a.picks[1].rank, 1); eq(a.picks[1].level, 10)
    eq(#a.picks, 4, "queue length")
end)

test("points saved up: queue simulates its own tier gates", function()
    local t = Snapshot("SHAMAN")
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end          -- AK 5/5
    for _ = 1, 2 do Learn(t, TA.Key(2, 2, 3)) end          -- Imp Ghost Wolf 2/2
    for _ = 1, 5 do Learn(t, TA.Key(2, 2, 2)) end          -- TS 5/5 -> 12 points
    local a = TA.Analyse(plan, t, 10)
    -- next: SF, IS, IS (15) then Flurry x5 (tier 4 opens at 15 via the queue itself)
    eq(a.picks[1].talent.name, "Shamanistic Focus")
    eq(a.picks[4].talent.name, "Flurry")
    assert(not a.picks[4].blocked, "Flurry should be open once queue reaches 15")
end)

test("off-plan points are reported and do not shift the plan", function()
    local t = Snapshot("SHAMAN")
    for _ = 1, 5 do Learn(t, TA.Key(3, 1, 3)) end          -- Totemic Focus 5/5 (Resto)
    local a = TA.Analyse(plan, t, 2)
    eq(#a.offPlan, 1, "off plan entries")
    eq(a.offPlan[1].talent.name, "Totemic Focus"); eq(a.offPlan[1].extra, 5)
    eq(a.picks[1].talent.name, "Ancestral Knowledge"); eq(a.spent, 5)
end)

test("a talent filled beyond the plan is off-plan only for the extra ranks", function()
    local t = Snapshot("SHAMAN")
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end
    for _ = 1, 3 do Learn(t, TA.Key(2, 2, 4)) end          -- Improved Shields 3/3 early (plan: 2 now, 1 later)
    local a = TA.Analyse(plan, t, 3)
    eq(#a.offPlan, 0, "3/3 is the plan total, nothing extra")
    eq(a.picks[1].talent.name, "Improved Ghost Wolf")
    local full = TA.Analyse(plan, t, 200)
    for _, p in ipairs(full.picks) do
        assert(p.talent.name ~= "Improved Shields", "Improved Shields re-suggested")
    end
end)

test("blocked pick names the missing points", function()
    local t = Snapshot("SHAMAN")
    for _ = 1, 5 do Learn(t, TA.Key(2, 1, 3)) end
    for _ = 1, 2 do Learn(t, TA.Key(2, 2, 3)) end
    for _ = 1, 5 do Learn(t, TA.Key(2, 2, 2)) end
    Learn(t, TA.Key(2, 3, 3)); Learn(t, TA.Key(2, 2, 4)); Learn(t, TA.Key(2, 2, 4))   -- 15
    t.points[2] = 12                                          -- pretend three were refunded
    local a = TA.Analyse(plan, t, 1)
    eq(a.picks[1].talent.name, "Flurry")
    assert(a.picks[1].blocked, "should be blocked"); eq(a.picks[1].need, 3)
end)

----------------------------------------------------------------------------
-- Gear scoring
----------------------------------------------------------------------------

local ENH = TalentAdvisorBuilds.SHAMAN.enhancement
local RESTO = TalentAdvisorBuilds.SHAMAN.restoration
local PROT = TalentAdvisorBuilds.WARRIOR.protection
local W = ENH.weights

local function item(id, loc, stats, speed, usable)
    return { id = id, link = "[" .. id .. "]", name = tostring(id), equipLoc = loc,
        stats = stats or {}, speed = speed, usable = usable ~= false, minLevel = 1 }
end

test("stat weights: AP is 1, strength counts double-ish", function()
    eq(TA.Score(item(1, "INVTYPE_CHEST", { AP = 10 }), W, nil, "melee"), 10)
    assert(TA.Score(item(1, "INVTYPE_CHEST", { STR = 10 }), W, nil, "melee") > 20)
end)

test("a rating that names a school counts only for that school", function()
    local spellCrit = item(1, "INVTYPE_CHEST", { CRIT_spell = 10 })
    local meleeCrit = item(2, "INVTYPE_CHEST", { CRIT_melee = 10 })
    local anyCrit = item(3, "INVTYPE_CHEST", { CRIT = 10 })
    eq(TA.Score(spellCrit, W, nil, "melee"), 0, "spell crit on a melee build")
    eq(TA.Score(meleeCrit, W, nil, "melee"), 10 * W.CRIT, "melee crit on a melee build")
    eq(TA.Score(anyCrit, W, nil, "melee"), 10 * W.CRIT, "plain crit always counts")
    local RW = RESTO.weights
    eq(TA.Score(meleeCrit, RW, nil, "spell"), 0, "melee crit on a caster build")
    eq(TA.Score(spellCrit, RW, nil, "spell"), 10 * RW.CRIT, "spell crit on a caster build")
end)

test("weapon: DPS and speed only count when a hand is given", function()
    local w = item(1, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.4)
    eq(TA.Score(w, W, nil, "melee"), 0)
    eq(TA.Score(w, W, "2H", "melee"), 20 * W.DPS_2H + 1.4 * W.SPEED_2H)
end)

test("slot upgrade with margin; equal-ish items are not suggested", function()
    local worn = { [5] = item(10, "INVTYPE_CHEST", { STA = 10, AGI = 10, ARMOR = 100 }) }
    local better = item(11, "INVTYPE_CHEST", { STA = 10, AGI = 14, ARMOR = 100 })
    local same = item(12, "INVTYPE_CHEST", { STA = 10, AGI = 10, ARMOR = 100 })
    local ups = TA.FindUpgrades({ { item = better, bag = 0, slot = 1 },
                                  { item = same, bag = 0, slot = 2 } }, worn, ENH, false)
    eq(#ups, 1); eq(ups[1].item.id, 11); eq(ups[1].invSlot, 5)
end)

test("an armour downgrade is refused however well it scores", function()
    local worn = { [5] = item(20, "INVTYPE_CHEST", { STA = 20, ARMOR = 400 }) }
    local cloth = item(21, "INVTYPE_CHEST", { INT = 200, SP = 200, ARMOR = 60 })
    local mail = item(22, "INVTYPE_CHEST", { INT = 30, SP = 40, ARMOR = 420 })
    eq(#TA.FindUpgrades({ { item = cloth, bag = 0, slot = 1 } }, worn, RESTO, false), 0, "cloth accepted")
    eq(#TA.FindUpgrades({ { item = mail, bag = 0, slot = 1 } }, worn, RESTO, false), 1, "mail refused")
    -- the floor is only about armour class, so it leaves rings and cloaks alone
    local ring = item(23, "INVTYPE_FINGER", { INT = 20, SP = 20 })
    eq(#TA.FindUpgrades({ { item = ring, bag = 0, slot = 1 } }, { [11] = item(24, "INVTYPE_FINGER", {}) },
        RESTO, false), 1, "ring refused")
end)

test("unusable (red tooltip line) and already-worn ids are skipped", function()
    local worn = { [11] = item(30, "INVTYPE_FINGER", { AP = 10 }) }
    local red = item(31, "INVTYPE_FINGER", { AP = 100 }, nil, false)
    local dup = item(30, "INVTYPE_FINGER", { AP = 10 })
    eq(#TA.FindUpgrades({ { item = red, bag = 0, slot = 1 },
                          { item = dup, bag = 0, slot = 2 } }, worn, ENH, false), 0)
end)

test("rings and trinkets replace the weaker of their two slots", function()
    local worn = { [11] = item(40, "INVTYPE_FINGER", { AP = 30 }), [12] = item(41, "INVTYPE_FINGER", { AP = 10 }) }
    local ring = item(42, "INVTYPE_FINGER", { AP = 20 })
    local ups = TA.FindUpgrades({ { item = ring, bag = 0, slot = 1 } }, worn, ENH, false)
    eq(#ups, 1); eq(ups[1].invSlot, 12)
end)

test("before dual wield: a slow two-hander beats a one-hander, a one-hander is not an off hand", function()
    local worn = { [16] = item(50, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.3) }
    local twoH = item(51, "INVTYPE_2HWEAPON", { DPS = 24 }, 3.5)
    local oneH = item(52, "INVTYPE_WEAPON", { DPS = 22 }, 2.6)
    local ups = TA.FindUpgrades({ { item = twoH, bag = 0, slot = 1 },
                                  { item = oneH, bag = 0, slot = 2 } }, worn, ENH, false)
    eq(#ups, 1); eq(ups[1].item.id, 51); eq(ups[1].invSlot, 16); assert(ups[1].weaponSet)
end)

test("with dual wield: a one-hander goes to the empty off hand next to the main hand", function()
    local worn = { [16] = item(60, "INVTYPE_WEAPON", { DPS = 30 }, 2.6) }
    local oneH = item(61, "INVTYPE_WEAPON", { DPS = 25 }, 2.5)
    local ups = TA.FindUpgrades({ { item = oneH, bag = 0, slot = 1 } }, worn, ENH, true)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
end)

test("with dual wield: a two-hander must beat both hands together", function()
    local worn = { [16] = item(70, "INVTYPE_WEAPON", { DPS = 30 }, 2.6),
                   [17] = item(71, "INVTYPE_WEAPON", { DPS = 28 }, 2.4) }
    local twoH = item(72, "INVTYPE_2HWEAPON", { DPS = 40 }, 3.4)
    eq(#TA.FindUpgrades({ { item = twoH, bag = 0, slot = 1 } }, worn, ENH, true), 0)
    local huge = item(73, "INVTYPE_2HWEAPON", { DPS = 60, STR = 30 }, 3.6)
    local ups = TA.FindUpgrades({ { item = huge, bag = 0, slot = 1 } }, worn, ENH, true)
    eq(#ups, 1); eq(ups[1].invSlot, 16)
end)

test("a better one-hander replaces the weaker hand, not the stronger", function()
    local worn = { [16] = item(80, "INVTYPE_WEAPON", { DPS = 30 }, 2.6),
                   [17] = item(81, "INVTYPE_WEAPON", { DPS = 15 }, 1.8) }
    local oneH = item(82, "INVTYPE_WEAPON", { DPS = 26 }, 2.5)
    local ups = TA.FindUpgrades({ { item = oneH, bag = 0, slot = 1 } }, worn, ENH, true)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
end)

test("shield goes to the off hand while a one-hander is worn, never next to a two-hander", function()
    local shield = item(90, "INVTYPE_SHIELD", { STA = 20, ARMOR = 500 })
    local ups = TA.FindUpgrades({ { item = shield, bag = 0, slot = 1 } },
        { [16] = item(91, "INVTYPE_WEAPON", { DPS = 20 }, 2.5) }, ENH, false)
    eq(#ups, 1); eq(ups[1].invSlot, 17)
    eq(#TA.FindUpgrades({ { item = shield, bag = 0, slot = 1 } },
        { [16] = item(92, "INVTYPE_2HWEAPON", { DPS = 20 }, 3.3) }, ENH, false), 0)
end)

test("a tank build values defense and stamina over raw attack power", function()
    local TW = PROT.weights
    local dps = item(100, "INVTYPE_HEAD", { AP = 40, ARMOR = 300 })
    local tank = item(101, "INVTYPE_HEAD", { STA = 20, DEF = 10, ARMOR = 300 })
    assert(TA.Score(tank, TW, nil, "melee") > TA.Score(dps, TW, nil, "melee"), "tank piece should win")
    assert(TA.Score(dps, W, nil, "melee") > TA.Score(tank, W, nil, "melee"), "dps piece should win for enhancement")
end)

test("upgrades are sorted by gain", function()
    local worn = { [1] = item(110, "INVTYPE_HEAD", { AP = 10, ARMOR = 100 }),
                   [8] = item(111, "INVTYPE_FEET", { AP = 10, ARMOR = 100 }) }
    local small = item(112, "INVTYPE_HEAD", { AP = 15, ARMOR = 100 })
    local big = item(113, "INVTYPE_FEET", { AP = 40, ARMOR = 100 })
    local ups = TA.FindUpgrades({ { item = small, bag = 0, slot = 1 },
                                  { item = big, bag = 0, slot = 2 } }, worn, ENH, false)
    eq(ups[1].item.id, 113); eq(ups[2].item.id, 112)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
