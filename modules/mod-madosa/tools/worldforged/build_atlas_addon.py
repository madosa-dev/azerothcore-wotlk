#!/usr/bin/env python3
"""Generate the WorldforgedAtlas addon's Data.lua from the live world database.

The addon draws a pin on the world map and the minimap for every Ascension
Worldforged find location, so this needs the same 1633 spots the server streams
caches at - and it takes them from the server's own table rather than
regenerating them from LootCollector, so the map cannot drift away from the
world. Item names and qualities come from item_template for the same reason:
whatever the server would actually hand out is what the tooltip promises.

Coordinates
-----------
mod_madosa_worldforged_ascension_spawns stores world coordinates, because that
is what the server spawns at. The world map wants the zone-relative fractions
those were converted *from*, so this inverts build_ascension_spawns.py's
zone_to_map() through the same WorldMapArea.dbc rows. The conversion is linear,
so the inverse is exact - and it is checked rather than assumed: a point that
does not land inside its own zone's 0..1 box is reported, not written.

Why not read LootCollector's percentages directly: the spawn table is the merged,
filtered, verified set. Going back to the raw discoveries would put pins at spots
the server has no cache at, which is worse than no pin at all.

Usage:
    build_atlas_addon.py            # write to stdout
    build_atlas_addon.py --write    # write addon/WorldforgedAtlas/Data.lua
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
MODULE = Path(__file__).resolve().parents[2]
DBC_DIR = HOME / "azerothcore/env/dist/data/dbc"
WORLDSERVER_CONF = HOME / "azerothcore/env/dist/etc/worldserver.conf"

sys.path.insert(0, str(MODULE / "tools/clientpatch"))

# Slots that carry no useful "where do I wear this" information for a filter.
INVENTORY_SLOT_NAMES = {
    1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist",
    7: "Legs", 8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket",
    13: "One-Hand", 14: "Off Hand", 15: "Ranged", 16: "Back", 17: "Two-Hand",
    18: "Bag", 19: "Tabard", 20: "Chest", 21: "Main Hand", 22: "Off Hand",
    23: "Held In Off-hand", 24: "Ammo", 25: "Thrown", 26: "Ranged", 28: "Relic",
}


# --------------------------------------------------------------------------
# The world database
# --------------------------------------------------------------------------

def db_settings():
    """host, port, user, password, database from worldserver.conf."""
    text = WORLDSERVER_CONF.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.M)
    if not m:
        raise SystemExit(f"no WorldDatabaseInfo in {WORLDSERVER_CONF}")
    parts = m.group(1).split(";")
    if len(parts) < 5:
        raise SystemExit(f"malformed WorldDatabaseInfo: {m.group(1)}")
    return parts[:5]


def query(sql):
    """Rows as lists of strings. --batch is tab separated and escapes \\t and \\n."""
    host, port, user, password, database = db_settings()
    out = subprocess.run(
        ["mysql", f"-h{host}", f"-P{port}", f"-u{user}", f"-p{password}",
         database, "-N", "-B", "-e", sql],
        capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"mysql failed: {out.stderr.strip()}")

    rows = []
    for line in out.stdout.splitlines():
        rows.append([f.replace("\\t", "\t").replace("\\n", "\n").replace("\\\\", "\\")
                     for f in line.split("\t")])
    return rows


def load_spawns():
    return [{"id": int(r[0]), "map": int(r[1]), "x": float(r[2]), "y": float(r[3]),
             "item": int(r[4]), "zone": r[5]}
            for r in query("SELECT id, map, position_x, position_y, item, zone "
                           "FROM mod_madosa_worldforged_ascension_spawns ORDER BY id")]


def load_items(entries):
    """entry -> name, quality, item level, inventory type, for the tooltip and filters."""
    ids = ",".join(str(e) for e in sorted(entries))
    rows = query("SELECT entry, name, Quality, ItemLevel, InventoryType "
                 f"FROM item_template WHERE entry IN ({ids})")
    return {int(r[0]): {"name": r[1], "quality": int(r[2]),
                        "level": int(r[3]), "slot": int(r[4])} for r in rows}


# --------------------------------------------------------------------------
# Coordinates
# --------------------------------------------------------------------------

def load_map_areas():
    """Zone name -> its WorldMapArea row, including the name GetMapInfo() returns.

    Keyed by AreaTable name because that is what the spawn table stores. The
    AreaName field (the map's texture directory, "Stranglethorn") is carried
    along because that is how the addon recognises the map currently shown.
    """
    from dbc import DBC, F

    areas = {}
    at = DBC(str(DBC_DIR / "AreaTable.dbc"))
    for r in at.rows():
        name = at.s(r[11])
        if name:
            areas.setdefault(name, r[0])

    wm = DBC(str(DBC_DIR / "WorldMapArea.dbc"))
    by_area = {}
    for r in wm.rows():
        by_area[r[2]] = {
            "texture": wm.s(r[3]),
            "y1": F(r[4]), "y2": F(r[5]),
            "x1": F(r[6]), "x2": F(r[7]),
        }

    return {zone: by_area[area] for zone, area in areas.items() if area in by_area}


def map_to_zone(world_x, world_y, e):
    """The exact inverse of build_ascension_spawns.py's zone_to_map().

    That one reads (x_pct, y_pct) as (across, down) and swaps them onto the
    world's (x = north-south, y = east-west), so unswapping is part of the
    inverse: world x came from y_pct through the x1..x2 bounds, world y from
    x_pct through y1..y2.
    """
    across = (world_y - e["y1"]) / (e["y2"] - e["y1"])
    down = (world_x - e["x1"]) / (e["x2"] - e["x1"])
    return across, down


# --------------------------------------------------------------------------

def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_lua(zones, items, dropped):
    out = []
    out.append("-- WorldforgedAtlas: every Ascension Worldforged find location.\n")
    out.append("--\n")
    out.append("-- GENERATED by mod-madosa/tools/worldforged/build_atlas_addon.py from the\n")
    out.append("-- server's own mod_madosa_worldforged_ascension_spawns and item_template -\n")
    out.append("-- re-run the tool rather than editing this file.\n")
    out.append("--\n")
    out.append(f"-- {sum(len(z['points']) // 3 for z in zones)} locations in {len(zones)} zones, "
               f"{len(items)} distinct items.\n")
    if dropped:
        out.append(f"-- {dropped} locations left out: no WorldMapArea row to place them on.\n")
    out.append("--\n")
    out.append("-- Positions are zone-relative fractions, 0,0 at the map's top left - the\n")
    out.append("-- form Astrolabe and the world map both want. `zone` is the name\n")
    out.append("-- GetMapZones() returns, `texture` the one GetMapInfo() does.\n")
    out.append("\n")
    out.append("local _, ns = ...\n\n")

    out.append("-- item id -> name, quality, item level, inventory type\n")
    out.append("ns.items = {\n")
    for entry in sorted(items):
        it = items[entry]
        out.append(f"    [{entry}] = {{{lua_string(it['name'])}, {it['quality']}, "
                   f"{it['level']}, {it['slot']}}},\n")
    out.append("}\n\n")

    out.append("-- Flat triples: across, down, item. Flat because 1633 three-field tables\n")
    out.append("-- cost more to load than the whole rest of the addon.\n")
    out.append("ns.zones = {\n")
    for z in zones:
        out.append(f"    {{zone = {lua_string(z['zone'])}, texture = {lua_string(z['texture'])},\n")
        out.append("     points = {")
        for i in range(0, len(z["points"]), 3):
            if i % 12 == 0:
                out.append("\n        ")
            across, down, item = z["points"][i], z["points"][i + 1], z["points"][i + 2]
            out.append(f"{across:.4f},{down:.4f},{item}, ")
        out.append("\n    }},\n")
    out.append("}\n")

    out.append("\nns.slotNames = {\n")
    for slot in sorted(INVENTORY_SLOT_NAMES):
        out.append(f"    [{slot}] = {lua_string(INVENTORY_SLOT_NAMES[slot])},\n")
    out.append("}\n")

    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="write addon/WorldforgedAtlas/Data.lua")
    args = ap.parse_args()

    spawns = load_spawns()
    if not spawns:
        raise SystemExit("no rows in mod_madosa_worldforged_ascension_spawns - "
                         "is worldforged_ascension_spawns.sql applied?")

    items = load_items({s["item"] for s in spawns})
    missing = {s["item"] for s in spawns} - set(items)
    if missing:
        print(f"{len(missing)} spawn items are not in item_template - "
              "is worldforged_ascension_items.sql applied?", file=sys.stderr)

    map_areas = load_map_areas()

    by_zone, dropped, outside = {}, 0, 0
    for s in spawns:
        entry = map_areas.get(s["zone"])
        if not entry or s["item"] not in items:
            dropped += 1
            continue

        across, down = map_to_zone(s["x"], s["y"], entry)

        # A point outside its own zone's box means the spawn row and the DBC
        # disagree about which zone it is in, and the pin would land somewhere
        # arbitrary. Leaving it out is better than pointing at the wrong hill.
        if not (0.0 <= across <= 1.0 and 0.0 <= down <= 1.0):
            outside += 1
            continue

        z = by_zone.setdefault(s["zone"], {"zone": s["zone"], "texture": entry["texture"],
                                           "points": []})
        z["points"] += [across, down, s["item"]]

    if outside:
        print(f"{outside} locations fall outside their own zone's map and were left out",
              file=sys.stderr)

    # Sorted so a regeneration produces a stable file instead of hash-order churn.
    zones = sorted(by_zone.values(), key=lambda z: z["zone"])

    lua = build_lua(zones, items, dropped + outside)
    if args.write:
        out = MODULE / "addon/WorldforgedAtlas/Data.lua"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(lua, encoding="utf-8")
        print(f"wrote {sum(len(z['points']) // 3 for z in zones)} locations to {out}",
              file=sys.stderr)
    else:
        sys.stdout.write(lua)

    print(f"{len(zones)} zones, {len(items)} items, {dropped} unplaceable", file=sys.stderr)


if __name__ == "__main__":
    main()
