-- lua5.1 snapshot.lua [<out dir>]
--
-- Lays the addon's frames out in the stand-in client and writes the resolved
-- rectangles to JSON, one file per view. render.py turns those into pictures
-- with the client's own font, which is the only way to look at this thing
-- without a game running.

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local out = arg[1] or (here .. "/../wowsim/snapshots")
local addon = here .. "/../../addon/TalentAdvisor"
dofile(here .. "/../wowsim/init.lua")
assert(Sim.LoadAddon(addon))

os.execute('mkdir -p "' .. out .. '"')

local function write(name, roots)
    local path = out .. "/" .. name .. ".json"
    Sim.Dump(path, roots)
    print("  " .. name)
end

-- The picker, as a fresh character of each class sees it.
for _, class in ipairs({ "SHAMAN", "WARRIOR", "PALADIN", "ROGUE" }) do
    World.Reset(class, 10)
    Sim.Event("PLAYER_LOGIN")
    write("picker-" .. class:lower(), { Sim.Picker() })
end

-- The advisor itself, mid-levelling, with a point in hand and things worth
-- wearing in the bags.
local function gearScene(class, build, level, items)
    World.Reset(class, level)
    TalentAdvisorCharDB = { build = build }
    for _, it in ipairs(items) do
        World.AddItem(it.key, it)
        if it.wear then World.Equip(it.wear, it.key) else World.PutInBag(0, it.bag, it.key) end
    end
    World.unspent = 1
    Sim.Login()
end

gearScene("SHAMAN", "enhancement", 34, {
    { key = "chest", id = 1, name = "Ravasaur Scale Breastplate", equipLoc = "INVTYPE_CHEST",
      stats = { STA = 12, AGI = 8, ARMOR = 380 }, wear = 5 },
    { key = "mh", id = 2, name = "Bloodletter", equipLoc = "INVTYPE_WEAPON",
      stats = { DPS = 22, STR = 4 }, speed = 2.6, wear = 16 },
    { key = "better", id = 3, name = "Girdle of Uther", equipLoc = "INVTYPE_CHEST",
      stats = { STA = 18, AGI = 16, STR = 10, ARMOR = 400 }, bag = 1 },
    { key = "axe", id = 4, name = "Ironfoe", equipLoc = "INVTYPE_2HWEAPON",
      stats = { DPS = 34, STR = 12 }, speed = 3.4, bag = 2 },
    { key = "ring", id = 5, name = "Band of the Hierophant", equipLoc = "INVTYPE_FINGER",
      stats = { AGI = 9, CRIT = 8 }, bag = 3 },
})
write("advisor-enhancement", { Sim.Frame() })

gearScene("PALADIN", "holy", 48, {
    { key = "chest", id = 10, name = "Chestplate of Tranquility", equipLoc = "INVTYPE_CHEST",
      stats = { STA = 14, INT = 12, SP = 20, ARMOR = 700 }, wear = 5 },
    { key = "cloth", id = 11, name = "Robe of the Archmage", equipLoc = "INVTYPE_CHEST",
      stats = { INT = 40, SP = 90, ARMOR = 90 }, bag = 1 },
    { key = "mail", id = 12, name = "Lightforge Breastplate", equipLoc = "INVTYPE_CHEST",
      stats = { STA = 18, INT = 20, SP = 35, MP5 = 6, ARMOR = 740 }, bag = 2 },
})
write("advisor-holy", { Sim.Frame() })

print("snapshots in " .. out)
