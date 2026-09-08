# pfquestgen — pfQuest's missing WotLK database, from your own realm

pfQuest ships Vanilla data dumped from VMaNGOS and TBC data from CMaNGOS, and
stops there. Its README says so outright, and so does every fork of it: the
addon runs on a 3.3.5 client but knows nothing north of Outland. In Northrend
it shows no quest nodes at all, on the world map or the minimap.

The gap is data, not code. pfQuest's loader already looks for a third layer:

```lua
for _, exp in pairs({ "-tbc", "-wotlk" }) do
  if pfDB[db]["data"..exp] then patchtable(pfDB[db]["data"], pfDB[db]["data"..exp]) end
```

`gen.py` writes that layer out of `acore_world`, which means the spawns are the
ones this realm actually has — module changes, custom content and all.

```sh
python3 gen.py --addon ~/path/to/Interface/AddOns/pfQuest-wotlk \
               --password <world db password>
```

It writes `db/*-wotlk.lua`, `db/enUS/*-wotlk.lua`, `init/data-wotlk.xml`,
`init/enUS-wotlk.xml`, and adds the two XML files to the `.toc`. Re-running is
safe: it rewrites the same files and does not duplicate the `.toc` lines.
**The client has to be restarted, not just reloaded** — the file list is read
once at startup.

## What it generates, and what it leaves alone

Everything pfQuest has no id for. A quest it already knows keeps the
hand-checked entry it shipped with; the rest — all of Northrend, the Death
Knight start, the WotLK instances — comes from the database. On this realm
that is roughly:

| | |
|---|---|
| quests | 2400 |
| units, with spawn points | 2800 |
| objects | 1350 |
| items, with their drop sources | 470 |
| zone names | 101 |
| minimap sizes | 36 |

about 1.4 MB, loaded at login like the rest of pfQuest's database.

**Zone names are overridden rather than filled in.** Blizzard reused old area
ids for Northrend, and pfQuest still carries the pre-WotLK names for them —
3537 is `"REUSE"`, 495 is `"DELETE ME"`, 65 is `"***On Map Dungeon***"`, 394 is
`"Darrowmere Lake UNUSED"`. pfQuest finds the current zone by looking its name
up in that table, so a stale name means no nodes even when the data is there.
`AreaTable.dbc` is what the client itself answers `GetRealZoneText()` with, so
it wins for every zone that has a world map.

## Coordinates

A spawn is a world position on a map; pfQuest wants a percentage inside a zone.
`WorldMapArea.dbc` gives every zone a rectangle in world coordinates:

```
x% = (locLeft - worldY) / (locLeft - locRight) * 100
y% = (locTop  - worldX) / (locTop  - locBottom) * 100
```

That was checked against pfQuest's own TBC data before a line of the generator
was written: of ten sampled spawns, nine land within 0.1% of the coordinate the
addon ships, and the tenth is a spawn AzerothCore places somewhere else than
CMaNGOS did. Zone sizes come out of the same rectangle — `locLeft - locRight`
by `locTop - locBottom` — and match pfQuest's own numbers exactly.

A spawn is assigned to the smallest zone rectangle on its map that contains it,
which is what puts a mob standing in a dungeon into the dungeon's map rather
than the continent's.

## Scrap

A world database keeps quests the game never shipped: placeholders, retired
text, scratch entries. Anything whose title is empty or reads `UNUSED`,
`DEPRECATED`, `NYI`, `[PH]` or `<...>` is dropped, as is any quest with no
giver, no turn-in and no objective — there would be nothing to draw. That takes
about 350 rows off the 2765 the query returns.

## What it cannot do

**Script-spawned mobs have no node.** An objective NPC that the core summons
rather than places has no row in `creature`, so there is no position to draw.
About 9% of the generated quests draw nothing for this reason, which is the
same limit pfQuest's hand-made vanilla data runs into.

**Sub-zone boxes are not generated.** `pfDB["zones"]["data"]` holds a
`{parent, width, height, x, y}` box per sub-area, used for "explore X"
objectives. Those rectangles are not in any DBC and are left alone.

## Checking it

`tools/wowsim` loads pfQuest for real and answers whether the data works:

```lua
dofile("tools/wowsim/init.lua")
assert(Sim.LoadAddon("<addons>/pfQuest-wotlk"))
print(pfMap:GetMapIDByName("Borean Tundra"))        -- 3537
pfDatabase:SearchQuestID(11561, { quest = "Them!" }) -- 26 node locations
```

That is how the numbers above were arrived at: 2183 of 2407 generated quests
put at least one node on a map, 43963 node locations in all, and standing on
one of them draws 14 pins on the minimap.
