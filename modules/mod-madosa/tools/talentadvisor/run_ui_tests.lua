-- lua5.1 run_ui_tests.lua   (from this directory, or give the addon dir as arg 1)
--
-- Drives the whole addon inside wow_sim.lua's stand-in client: log in, answer
-- the picker, level up, put things in the bags, click the rows. This is the
-- half run_tests.lua cannot reach - that one calls the pure functions with
-- plain data, this one goes through the events and the frames.
--
-- Geometry is real here: wow_layout.lua resolves the anchors and measures the
-- strings with the client's own font, so the layout assertions are about
-- whether things actually fit, not whether a guessed number came out positive.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local addon = arg[1] or (here .. "/../../addon/TalentAdvisor")
dofile(here .. "/../wowsim/init.lua")
assert(Sim.LoadAddon(addon))

-- TalentAdvisor caches the chosen build on its own table, which outlives a
-- scenario because the addon is only loaded once.
World.OnReset(function()
    local st = TalentAdvisor.state
    st.build, st.plan, st.buildKey, st.talents, st.analysis = nil, nil, nil, nil, nil
    st.upgrades, st.announced, st.worn = {}, {}, nil
    st.dirtyGear, st.pendingItems = false, false
end)
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

test("the picker names the class it is asking about", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        World.Reset(class, 10)
        Sim.Event("PLAYER_LOGIN")
        has(Sim.Picker().title:GetText(), (UnitClass("player")), class .. " picker title")
    end
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
        if h:IsShown() then assert(h:GetNumPoints() > 0, "a header is not anchored") end
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
-- Layout
--
-- These are the checks the old inert stub could not make: the anchors are
-- resolved and the strings measured with the client's font, so "does the
-- panel actually cover its own contents" has an answer.
----------------------------------------------------------------------------

-- A close button is meant to hang over the corner of its frame; everything
-- else has to stay inside.
local function overhangs(w) return w._template == "UIPanelCloseButton" end

local function assertInside(frame, what)
    for _, w in ipairs(Sim.Tree(frame)) do
        if w ~= frame and not overhangs(w) then
            local ok, side = Layout.Contains(frame, w, 0.5)
            if not ok then
                local label = (w.GetText and w:GetText()) and Layout.Visible(w:GetText()) or w._kind
                error(what .. ": " .. label .. " sticks out of the " .. side, 2)
            end
        end
    end
end

test("the picker covers its own contents, for every class", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        World.Reset(class, 10)
        Sim.Event("PLAYER_LOGIN")
        local p = Sim.Picker()
        assertInside(p, class .. " picker")
        local ok, side = Layout.Contains(UIParent, p)
        assert(ok, class .. " picker runs off the " .. tostring(side) .. " of the screen")
    end
end)

test("the group headings line up with each other", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        World.Reset(class, 10)
        Sim.Event("PLAYER_LOGIN")
        local left
        for _, h in ipairs(Sim.Picker().headers) do
            if h:IsShown() then
                local l = Layout.Rect(h)
                if left then
                    assert(math.abs(l - left) < 0.5,
                        class .. ": '" .. h:GetText() .. "' is at " .. l .. ", the heading above it at " .. left)
                end
                left = l
            end
        end
    end
end)

test("picker rows do not run into each other or into the footer", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        World.Reset(class, 10)
        Sim.Event("PLAYER_LOGIN")
        local p = Sim.Picker()
        local rows = Sim.PickerRows()
        for i = 2, #rows do
            assert(not Layout.Overlaps(rows[i - 1], rows[i]), class .. ": rows overlap")
        end
        local _, lastBottom = Layout.Rect(rows[#rows])
        local _, _, _, footTop = Layout.Rect(p.foot)
        assert(lastBottom - footTop >= 8,
            string.format("%s: only %.1fpx between the last row and the footer", class, lastBottom - footTop))
    end
end)

test("a build's name and description fit the row they are drawn in", function()
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        World.Reset(class, 10)
        Sim.Event("PLAYER_LOGIN")
        for _, row in ipairs(Sim.PickerRows()) do
            -- the room a line has is the row's, not the string's own: a
            -- FontString anchored on one side only is exactly as wide as its
            -- text and would always look like a perfect fit
            local room = row:GetWidth() - 8
            for _, fs in ipairs({ row.name, row.desc }) do
                local font = Layout.FontOf(fs)
                local lines = Layout.Wrap(fs:GetText(), font, room)
                assert(#lines == 1, string.format("%s/%s: %q needs %d lines in %.0fpx",
                    class, row.buildKey, Layout.Visible(fs:GetText()), #lines, room))
                -- fitting exactly is not fitting: leave room for a longer
                -- font, a longer translation, or one more word
                local used = Layout.Width(Layout.Visible(fs:GetText()), font) / room
                assert(used <= 0.94, string.format("%s/%s: %q fills %.0f%% of its row",
                    class, row.buildKey, Layout.Visible(fs:GetText()), used * 100))
            end
            local ok, side = Layout.Contains(row, row.desc, 0.5)
            assert(ok, class .. "/" .. row.buildKey .. ": the description leaves the row at the " .. tostring(side))
        end
    end
end)

test("a build name does not repeat the heading it sits under", function()
    local role = { melee = "melee", caster = "caster", heal = "heal", tank = "tank" }
    for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
        for _, group in ipairs(TA.BuildsByRole(class)) do
            for _, e in ipairs(group.builds) do
                local lower = e.build.name:lower()
                assert(not lower:find(role[group.role], 1, true),
                    class .. "/" .. e.key .. ": the name says '" .. group.role
                        .. "' and so does the heading above it")
            end
        end
    end
end)

test("the advisor frame covers its contents, full of gear and a two-line queue", function()
    World.Reset("SHAMAN", 40)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.SetRank(3, 1, 3, 5)                     -- off-plan points, so the queue wraps
    World.AddItem("worn", { id = 200, name = "worn", equipLoc = "INVTYPE_CHEST",
        stats = { AP = 10, ARMOR = 400 } })
    World.Equip(5, "worn")
    for i = 1, 8 do                               -- more upgrades than the frame has rows
        World.AddItem("up" .. i, { id = 200 + i, name = "Upgrade Number " .. i,
            equipLoc = "INVTYPE_CHEST", stats = { AP = 20 + i * 10, STR = 10, ARMOR = 420 } })
        World.PutInBag(0, i, "up" .. i)
    end
    World.unspent = 1
    Sim.Login()
    local f = Sim.Frame()
    assertInside(f, "advisor frame")
    local ok, side = Layout.Contains(UIParent, f)
    assert(ok, "the advisor frame runs off the " .. tostring(side) .. " of the screen")
    assert(not Layout.Overlaps(f.title, f.close), "the title runs under the close button")
    assert(not Layout.Overlaps(f.next, f.learn), "the next pick runs under the Learn button")

    -- every line in the frame has one line of room; a string that wraps
    -- pushes its own box down over whatever is under it
    for _, fs in ipairs({ f.title, f.next, f.sub, f.gearTitle }) do
        local lines = Layout.Wrap(fs:GetText(), Layout.FontOf(fs), fs:GetWidth())
        assert(#lines == 1, string.format("%q wraps to %d lines in %.0fpx",
            Layout.Visible(fs:GetText()), #lines, fs:GetWidth()))
    end
    for _, pair in ipairs({ { f.title, f.icon }, { f.title, f.next }, { f.next, f.sub },
                           { f.sub, f.queue }, { f.queue, f.gearTitle } }) do
        assert(not Layout.Overlaps(pair[1], pair[2]),
            "two of the frame's own lines overlap: " ..
            tostring(Layout.Visible(pair[1]:GetText() or "")):sub(1, 30))
    end
    assert(#Sim.GearRows() == 6, "the frame should cap at its six rows")

    -- the height is worked out by hand in Render(); this is what says the sum
    -- still matches where the rows actually end up
    local _, frameBottom = Layout.Rect(f)
    local lowest
    for _, w in ipairs(Sim.Tree(f)) do
        if w ~= f then
            local _, b = Layout.Rect(w)
            if not lowest or b < lowest then lowest = b end
        end
    end
    local padding = lowest - frameBottom
    assert(padding >= 4 and padding <= 32,
        string.format("%.1fpx of padding under the last row - the height sum has drifted", padding))
end)

----------------------------------------------------------------------------
-- The awkward states
----------------------------------------------------------------------------

test("the tree arriving late is waited for, not mistaken for a wrong build", function()
    World.Reset("SHAMAN", 30)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.talentsLoaded = false          -- the moment after login on a real server
    Sim.Event("PLAYER_LOGIN")
    Sim.Events():Fire("OnUpdate", 1.0)
    local f = Sim.Frame()
    assert(not Sim.ChatHas("does not match"), "the addon accused the build")
    has(f.next:GetText(), "Waiting for the talent tree", "frame while the tree is missing")
    assert(not f.learn:IsShown(), "Learn offered with no tree to learn from")

    Sim.TalentsArrive()
    has(Sim.Frame().next:GetText(), "Ancestral Knowledge", "first pick once the tree is here")
    has(Sim.Chat(), "next: Ancestral Knowledge", "the announcement waited for the tree")
    has(Sim.Chat(), "/ta pick", "and says how to change build")
end)

test("the tree turning up on its own poll is enough - no event needed", function()
    World.Reset("SHAMAN", 30)
    TalentAdvisorCharDB = { build = "enhancement" }
    World.talentsLoaded = false
    Sim.Event("PLAYER_LOGIN")
    Sim.Events():Fire("OnUpdate", 1.0)
    has(Sim.Frame().next:GetText(), "Waiting", "still waiting")
    World.talentsLoaded = true           -- no event, just data appearing
    Sim.Events():Fire("OnUpdate", 1.0)
    Sim.Tick()
    has(Sim.Frame().next:GetText(), "Ancestral Knowledge", "picked up by polling")
end)

test("a build really meant for another class says so, and says what to do", function()
    World.Reset("WARRIOR", 30)
    TalentAdvisorCharDB = { build = "arms" }
    Sim.Login()
    -- swap the plan under it for a shaman one, the way a stale saved variable
    -- from another character would
    TalentAdvisor.state.plan = TalentAdvisor.ExpandPlan(TalentAdvisorBuilds.SHAMAN.restoration)
    TA.RefreshTalents()
    TA.Render()
    has(Sim.Frame().next:GetText(), "not for this class", "the real mismatch case")
    has(Sim.Frame().sub:GetText(), "/ta pick", "and how to fix it")
end)

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
