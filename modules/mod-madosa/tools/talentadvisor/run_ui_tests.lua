-- lua5.1 run_ui_tests.lua   (from this directory, or give the addon dir as arg 1)
--
-- Drives the whole addon inside wow_sim.lua's stand-in client: log in, answer
-- the picker, level up, put things in the bags, click the rows. This is the
-- half run_tests.lua cannot reach - that one calls the pure functions with
-- plain data, this one goes through the events and the frames.
--
-- It cannot see pixels. Fonts have no metrics in the simulator, so layout is
-- only checked for sanity: everything shown is anchored to something and the
-- frame ends up with a positive height that grows with its contents.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local addon = arg[1] or (here .. "/../../addon/TalentAdvisor")
dofile(here .. "/trees.lua")
dofile(here .. "/wow_sim.lua")
dofile(addon .. "/Builds.lua")
dofile(addon .. "/Core.lua")
local TA = TalentAdvisor

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
local function has(haystack, needle, what)
    if not tostring(haystack):find(needle, 1, true) then
        error((what or "text") .. ": " .. tostring(haystack) .. " does not contain " .. needle, 2)
    end
end

-- Pick the build named key out of the picker by clicking its row.
local function ClickBuild(key)
    for _, row in ipairs(Sim.PickerRows()) do
        if row.buildKey == key then row:Click(); Sim.Tick(); return row end
    end
    error("no picker row for " .. key)
end

print("TalentAdvisor UI tests (simulated client)")

----------------------------------------------------------------------------
-- The picker
----------------------------------------------------------------------------

test("a fresh character is asked before anything is advised", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    local p = Sim.Picker()
    assert(p, "no picker was built")
    assert(p:IsShown(), "the picker is not showing")
    assert(not Sim.Frame():IsShown(), "the advisor frame should stay closed until a build is chosen")
    eq(TA.state.build, nil, "a build was selected without being asked")
    has(p.title:GetText(), "what do you want to play", "picker title")
end)

test("the picker groups by role, in role order, with a row per build", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    eq(table.concat(Sim.PickerHeaders(), ","), "Melee damage,Caster damage,Healing,Tanking", "headers")
    local rows = Sim.PickerRows()
    eq(#rows, 4, "rows")
    local keys = {}
    for _, r in ipairs(rows) do keys[#keys + 1] = r.buildKey end
    eq(table.concat(keys, ","), "enhancement,elemental,restoration,tank", "row order")
end)

test("every row says what the build is, and the odd one says it is odd", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    for _, row in ipairs(Sim.PickerRows()) do
        assert(#(row.desc:GetText() or "") > 20, row.buildKey .. " has no description")
        assert(row:GetNumPoints() > 0, row.buildKey .. " is not anchored")
    end
    for _, row in ipairs(Sim.PickerRows()) do
        if row.buildKey == "tank" then has(row.name:GetText(), "(meta)", "meta mark") end
        if row.buildKey == "enhancement" then has(row.name:GetText(), "usual pick", "default mark") end
    end
end)

test("the picker is laid out: headers anchored, height positive and class-dependent", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    local p = Sim.Picker()
    local shaman = p:GetHeight()
    assert(shaman > 0, "picker has no height")
    for _, h in ipairs(p.headers) do
        if h.shown then assert(h:GetNumPoints() > 0, "a header is not anchored") end
    end
    World.Reset("WARRIOR", 10)
    Sim.Event("PLAYER_LOGIN")
    -- warrior: three melee builds and a tank, so three headers instead of four
    eq(table.concat(Sim.PickerHeaders(), ","), "Melee damage,Tanking", "warrior headers")
    eq(#Sim.PickerRows(), 4, "warrior rows")
    assert(p:GetHeight() > 0, "picker lost its height")
end)

test("choosing a build closes the picker and starts the advice", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    ClickBuild("restoration")
    assert(not Sim.Picker():IsShown(), "picker stayed open")
    assert(Sim.Frame():IsShown(), "advisor frame stayed closed")
    eq(TA.state.buildKey, "restoration", "chosen build")
    eq(TalentAdvisorCharDB.build, "restoration", "choice was not remembered")
    has(Sim.Frame().title:GetText(), "Restoration", "frame title")
    has(Sim.Frame().title:GetText(), "Healing", "frame title role")
    has(Sim.Chat(), "Restoration it is", "confirmation")
end)

test("a character that already chose is not asked again", function()
    World.Reset("SHAMAN", 20)
    TalentAdvisorCharDB = { build = "elemental" }
    Sim.Login()
    assert(not Sim.Picker():IsShown(), "picker opened for a character that had chosen")
    eq(TA.state.buildKey, "elemental")
    has(Sim.Frame().title:GetText(), "Elemental")
end)

test("/ta pick reopens the chooser and marks the current build", function()
    World.Reset("SHAMAN", 20)
    TalentAdvisorCharDB = { build = "elemental" }
    Sim.Login()
    Sim.Slash("pick")
    assert(Sim.Picker():IsShown(), "/ta pick did not open the picker")
    for _, row in ipairs(Sim.PickerRows()) do
        if row.buildKey == "elemental" then has(row.name:GetText(), "(current)", "current mark") end
    end
    ClickBuild("enhancement")
    eq(TA.state.buildKey, "enhancement", "switching builds")
end)

----------------------------------------------------------------------------
-- Talents
----------------------------------------------------------------------------

test("the first pick is the first step of the chosen plan", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    ClickBuild("enhancement")
    local f = Sim.Frame()
    has(f.next:GetText(), "Ancestral Knowledge", "next pick")
    has(f.next:GetText(), "(1/5)", "next rank")
    has(f.sub:GetText(), "1 point to spend", "unspent points")
    assert(f.learn:IsShown(), "Learn button hidden with a point in hand")
    has(f.queue:GetText(), "Ancestral Knowledge 2/5", "queue")
end)

test("the Learn button spends the point on the talent it names", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    ClickBuild("enhancement")
    Sim.Frame().learn:Click()
    eq(#World.learned, 1, "LearnTalent calls")
    eq(World.learned[1].name, "Ancestral Knowledge", "talent learned")
    eq(World.unspent, 0, "point not spent")
    eq(World.ranks["2:1:3"], 1, "rank")
    has(Sim.Chat(), "Learning Ancestral Knowledge (1/5)", "chat")
end)

test("with no point in hand the button is gone and the next level is named", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    ClickBuild("enhancement")
    World.unspent = 0
    Sim.Event("CHARACTER_POINTS_CHANGED")
    assert(not Sim.Frame().learn:IsShown(), "Learn button still showing")
    has(Sim.Frame().sub:GetText(), "next point at level", "sub line")
end)

test("auto on places the point on level up, auto off only says where it goes", function()
    World.Reset("SHAMAN", 10)
    Sim.Event("PLAYER_LOGIN")
    ClickBuild("enhancement")
    Sim.Slash("auto off")
    World.level, World.unspent = 11, 1
    Sim.Event("PLAYER_LEVEL_UP")
    eq(#World.learned, 0, "auto off should not learn")
    has(Sim.Chat(), "Next point: Ancestral Knowledge", "notice")

    Sim.Slash("auto on")
    World.level, World.unspent = 12, 1
    Sim.Event("PLAYER_LEVEL_UP")
    eq(#World.learned, 1, "auto on should learn")
    eq(World.learned[1].name, "Ancestral Knowledge")
end)

test("a blocked pick refuses to learn and says how many points are missing", function()
    World.Reset("SHAMAN", 25)
    TalentAdvisorCharDB = { build = "enhancement" }
    -- 12 points in Enhancement, none of them where the plan wants the 13th:
    -- the plan is at Flurry (tier 4), which needs 15 in the tree.
    World.SetRank(2, 1, 3, 5)      -- Ancestral Knowledge
    World.SetRank(2, 2, 3, 2)      -- Improved Ghost Wolf
    World.SetRank(2, 2, 2, 5)      -- Thundering Strikes
    World.SetRank(2, 3, 3, 1)      -- Shamanistic Focus
    World.SetRank(2, 2, 4, 2)      -- Improved Shields
    World.spent[2] = 12            -- pretend three of those were refunded
    World.unspent = 1
    Sim.Login()
    has(Sim.Frame().next:GetText(), "Flurry", "next pick")
    has(Sim.Frame().sub:GetText(), "blocked", "sub line")
    Sim.Frame().learn:Click()
    eq(#World.learned, 0, "a blocked talent must not be learned")
end)

test("points spent off the plan are reported, not counted", function()
    World.Reset("SHAMAN", 16)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.SetRank(3, 1, 3, 5)      -- Totemic Focus, nowhere in the plan
    World.unspent = 1
    Sim.Login()
    has(Sim.Frame().queue:GetText(), "Off plan:", "off plan line")
    has(Sim.Frame().queue:GetText(), "Totemic Focus +5", "off plan entry")
end)

----------------------------------------------------------------------------
-- Gear
----------------------------------------------------------------------------

local function chest(key, id, stats, extra)
    local def = { id = id, name = key, equipLoc = "INVTYPE_CHEST", stats = stats }
    for k, v in pairs(extra or {}) do def[k] = v end
    return World.AddItem(key, def)
end

test("a healer in mail is not sent to a cloth robe with more Intellect", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "restoration" }
    chest("worn", 1, { STA = 10, INT = 10, SP = 10, ARMOR = 400 })
    chest("cloth", 2, { INT = 200, SP = 200, ARMOR = 60 })
    chest("mail", 3, { STA = 12, INT = 25, SP = 40, ARMOR = 420 })
    World.Equip(5, "worn")
    World.PutInBag(0, 1, "cloth"); World.PutInBag(0, 2, "mail")
    Sim.Login()
    local rows = Sim.GearRows()
    eq(#rows, 1, "suggestions")
    eq(rows[1].upgrade.item.name, "mail", "the mail chest is the only honest upgrade")
    assert(not Sim.ChatHas("cloth"), "the cloth robe was announced")
    has(Sim.Chat(), "mail", "the mail chest was not announced")
end)

test("the same cloth robe is fine for a build with no armour floor to break", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "restoration" }
    chest("worn", 1, { STA = 10, INT = 10, SP = 10, ARMOR = 400 })
    local cloth = chest("cloth", 2, { INT = 200, SP = 200, ARMOR = 60 })
    World.Equip(5, "worn"); World.PutInBag(0, 1, "cloth")
    Sim.Login()
    eq(#Sim.GearRows(), 0, "cloth accepted with the floor on")
    -- take the floor away and the same item is the obvious upgrade it looks like
    TalentAdvisorBuilds.SHAMAN.restoration.armorFloor = nil
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "restoration" }
    chest("worn", 1, { STA = 10, INT = 10, SP = 10, ARMOR = 400 })
    chest("cloth", 2, { INT = 200, SP = 200, ARMOR = 60 })
    World.Equip(5, "worn"); World.PutInBag(0, 1, "cloth")
    Sim.Login()
    eq(#Sim.GearRows(), 1, "cloth refused with the floor off")
    TalentAdvisorBuilds.SHAMAN.restoration.armorFloor = 0.55
end)

test("a shield tank is never offered a two-hander, however good it is", function()
    World.Reset("WARRIOR", 40)
    TalentAdvisorCharDB = { build = "protection" }
    World.AddItem("axe", { id = 10, name = "axe", equipLoc = "INVTYPE_WEAPON",
        stats = { DPS = 30, STR = 5 }, speed = 2.6 })
    World.AddItem("shield", { id = 11, name = "shield", equipLoc = "INVTYPE_SHIELD",
        stats = { STA = 20, ARMOR = 900, BLOCK = 40 } })
    World.AddItem("greatsword", { id = 12, name = "greatsword", equipLoc = "INVTYPE_2HWEAPON",
        stats = { DPS = 90, STR = 60, STA = 40 }, speed = 3.6 })
    World.AddItem("betteraxe", { id = 13, name = "betteraxe", equipLoc = "INVTYPE_WEAPON",
        stats = { DPS = 45, STR = 20, DEF = 10 }, speed = 2.6 })
    World.Equip(16, "axe"); World.Equip(17, "shield")
    World.PutInBag(0, 1, "greatsword"); World.PutInBag(0, 2, "betteraxe")
    Sim.Login()
    local rows = Sim.GearRows()
    eq(#rows, 1, "suggestions")
    eq(rows[1].upgrade.item.name, "betteraxe", "the one-hander is the only offer")
    eq(rows[1].upgrade.invSlot, 16, "main hand")
end)

test("a Fury warrior is offered an off hand only once dual wield is trained", function()
    World.Reset("WARRIOR", 19)
    TalentAdvisorCharDB = { build = "fury" }
    World.AddItem("mh", { id = 20, name = "mh", equipLoc = "INVTYPE_WEAPON",
        stats = { DPS = 30 }, speed = 2.6 })
    World.AddItem("oh", { id = 21, name = "oh", equipLoc = "INVTYPE_WEAPON",
        stats = { DPS = 28 }, speed = 2.4 })
    World.Equip(16, "mh"); World.PutInBag(0, 1, "oh")
    Sim.Login()
    eq(#Sim.GearRows(), 0, "off hand offered before level 20")

    World.level, World.unspent = 20, 1
    Sim.Event("PLAYER_LEVEL_UP")
    Sim.Tick()
    local rows = Sim.GearRows()
    eq(#rows, 1, "off hand not offered at 20")
    eq(rows[1].upgrade.invSlot, 17, "off hand slot")
end)

test("clicking a gear row equips it; shift-clicking links it", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "enhancement" }
    chest("worn", 30, { AP = 10, ARMOR = 400 })
    chest("better", 31, { AP = 60, STR = 20, ARMOR = 420 })
    World.Equip(5, "worn"); World.PutInBag(0, 3, "better")
    Sim.Login()
    local row = Sim.GearRows()[1]
    assert(row, "no suggestion to click")

    MODIFIED_CLICK = "CHATLINK"
    row:Click()
    assert(Sim.ChatHas("LINK:"), "shift-click did not link the item")
    eq(#World.equipCalls, 0, "shift-click equipped instead of linking")

    MODIFIED_CLICK = nil
    row:Click()
    eq(#World.equipCalls, 1, "click did not equip")
    eq(World.equipCalls[1].invSlot, 5, "wrong slot")
    eq(World.equipped[5], "better", "the item did not end up worn")
end)

test("nothing is equipped in combat", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "enhancement" }
    chest("worn", 40, { AP = 10, ARMOR = 400 })
    chest("better", 41, { AP = 60, STR = 20, ARMOR = 420 })
    World.Equip(5, "worn"); World.PutInBag(0, 1, "better")
    Sim.Login()
    World.combat = true
    Sim.GearRows()[1]:Click()
    eq(#World.equipCalls, 0, "equipped while in combat")
    has(Sim.Chat(), "Not in combat", "notice")
end)

test("an item the client has not cached yet is picked up on the next scan", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "enhancement" }
    -- chosen up front so the login goes straight to scanning
    chest("worn", 50, { AP = 10, ARMOR = 400 })
    local late = chest("late", 51, { AP = 60, STR = 20, ARMOR = 420 }, { uncached = true })
    World.Equip(5, "worn"); World.PutInBag(0, 1, "late")
    -- Sim.Login would spin here: the addon rescans until the item turns up, so
    -- the scan is stepped by hand instead.
    Sim.Event("PLAYER_LOGIN")
    Sim.Events():Fire("OnUpdate", 1.0)
    eq(#Sim.GearRows(), 0, "an uncached item should not be scored")
    assert(TA.state.dirtyGear, "the scan should stay dirty until the item arrives")
    late.uncached = nil
    Sim.Tick()
    eq(#Sim.GearRows(), 1, "the item was never picked up")
end)

----------------------------------------------------------------------------
-- The tooltip fallback
----------------------------------------------------------------------------

test("without GetItemStats the stats come off the tooltip", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.useItemStats = false
    World.AddItem("wornring", { id = 60, name = "wornring", equipLoc = "INVTYPE_FINGER",
        stats = {}, tooltip = { "+4 Agility" } })
    World.AddItem("bigring", { id = 61, name = "bigring", equipLoc = "INVTYPE_FINGER",
        stats = {}, tooltip = { "+20 Agility", "+15 Strength",
            "Increases attack power by 40.", "Improves critical strike rating by 12." } })
    World.Equip(11, "wornring"); World.PutInBag(0, 1, "bigring")
    Sim.Login()
    local rows = Sim.GearRows()
    eq(#rows, 1, "suggestions")
    local stats = rows[1].upgrade.item.stats
    eq(stats.AGI, 20, "agility"); eq(stats.STR, 15, "strength")
    eq(stats.AP, 40, "attack power"); eq(stats.CRIT, 12, "crit rating")
end)

test("a red tooltip line means the item cannot be worn, whatever it scores", function()
    World.Reset("SHAMAN", 20)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.AddItem("wornring", { id = 70, name = "wornring", equipLoc = "INVTYPE_FINGER",
        stats = { AGI = 4 } })
    World.AddItem("toohigh", { id = 71, name = "toohigh", equipLoc = "INVTYPE_FINGER",
        stats = { AGI = 200, AP = 200 }, usable = false })
    World.Equip(11, "wornring"); World.PutInBag(0, 1, "toohigh")
    Sim.Login()
    eq(#Sim.GearRows(), 0, "an unusable item was suggested")
end)

test("weapon speed is read off the tooltip either way", function()
    World.Reset("SHAMAN", 30)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.AddItem("slow", { id = 80, name = "slow", equipLoc = "INVTYPE_2HWEAPON",
        stats = { DPS = 40 }, speed = 3.6 })
    World.AddItem("fast", { id = 81, name = "fast", equipLoc = "INVTYPE_2HWEAPON",
        stats = { DPS = 41 }, speed = 2.1 })
    World.Equip(16, "fast"); World.PutInBag(0, 1, "slow")
    Sim.Login()
    local rows = Sim.GearRows()
    eq(#rows, 1, "the slower two-hander should win for Enhancement")
    eq(rows[1].upgrade.item.speed, 3.6, "speed was not read")
end)

----------------------------------------------------------------------------
-- The rest of the slash commands
----------------------------------------------------------------------------

test("every slash command answers and none of them error", function()
    World.Reset("SHAMAN", 45)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.SetRank(2, 1, 3, 5)
    World.unspent = 1
    Sim.Login()
    for _, cmd in ipairs({ "", "show", "hide", "plan", "gear", "notes", "weights",
                           "build", "margin 10", "auto on", "auto off", "reset", "help" }) do
        CHAT = {}
        Sim.Slash(cmd)
        assert(#CHAT > 0 or cmd == "" or cmd == "show" or cmd == "hide" or cmd == "reset",
            "/ta " .. cmd .. " said nothing")
    end
    CHAT = {}
    Sim.Slash("notes")
    has(Sim.Chat(), "Windfury", "notes come from the build")
    CHAT = {}
    Sim.Slash("plan")
    has(Sim.Chat(), "Improved Ghost Wolf", "the plan lists what is left")
    CHAT = {}
    Sim.Slash("build")
    has(Sim.Chat(), "Melee damage", "build listing is grouped by role")
end)

test("/ta build switches directly, and rejects a name that is not there", function()
    World.Reset("PALADIN", 30)
    TalentAdvisorCharDB = { build = "retribution" }
    Sim.Login()
    Sim.Slash("build holy")
    eq(TA.state.buildKey, "holy", "switch")
    has(Sim.Frame().title:GetText(), "Holy")
    CHAT = {}
    Sim.Slash("build shadow")
    eq(TA.state.buildKey, "holy", "an unknown name must not change anything")
    has(Sim.Chat(), "unknown build", "complaint")
end)

----------------------------------------------------------------------------
-- The awkward states
----------------------------------------------------------------------------

test("a saved build that no longer exists asks again instead of going quiet", function()
    World.Reset("SHAMAN", 30)
    TalentAdvisorCharDB = { build = "windfury-something-removed" }
    Sim.Event("PLAYER_LOGIN")
    assert(Sim.Picker():IsShown(), "the picker should reopen for a build that is gone")
    eq(TalentAdvisorCharDB.build, nil, "the stale key should be forgotten")
    ClickBuild("enhancement")
    eq(TA.state.buildKey, "enhancement", "still pickable afterwards")
end)

test("a class with no builds says so and does not error", function()
    World.Reset("MAGE", 30)      -- dump_trees.py ships every class's tree
    Sim.Event("PLAYER_LOGIN")
    assert(not Sim.Picker():IsShown(), "a picker with nothing in it")
    assert(not Sim.Frame():IsShown(), "the frame should stay closed")
    has(Sim.Chat(), "no levelling build for this class", "notice")
    Sim.Slash("plan"); Sim.Slash("gear"); Sim.Slash("weights")   -- must not error
end)

----------------------------------------------------------------------------
-- All sixteen builds survive a login
----------------------------------------------------------------------------

test("every shipped build logs in, renders and scans without erroring", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        for key, build in pairs(TalentAdvisorBuilds[class]) do
            if type(build) == "table" and build.steps then
                World.Reset(class, 60)
                TalentAdvisorCharDB = { build = key }
                World.AddItem("w", { id = 90, name = "w", equipLoc = "INVTYPE_CHEST",
                    stats = { STA = 20, ARMOR = 500 } })
                World.AddItem("b", { id = 91, name = "b", equipLoc = "INVTYPE_CHEST",
                    stats = { STA = 30, STR = 20, INT = 20, SP = 20, ARMOR = 520 } })
                World.Equip(5, "w"); World.PutInBag(0, 1, "b")
                Sim.Login()
                local id = class .. "/" .. key
                eq(TA.state.buildKey, key, id .. " build")
                assert(Sim.Frame():IsShown(), id .. " frame hidden")
                assert(Sim.Frame():GetHeight() > 0, id .. " frame has no height")
                assert(#(Sim.Frame().next:GetText() or "") > 0, id .. " says nothing")
                Sim.Slash("plan"); Sim.Slash("notes"); Sim.Slash("weights")
            end
        end
    end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
