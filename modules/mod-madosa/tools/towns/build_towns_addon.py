#!/usr/bin/env python3
"""Generate WorldforgedAtlas' Towns.lua: every town and city, as a teleport target.

MultiBot's Necro-Network puts a button on every graveyard and teleports with
`.go graveyard <id>`, so the addon never needs a coordinate - the server looks
the graveyard up by id. There is no `.go town`, so a town layer has to carry its
own positions, and this writes them.

Where the towns come from
-------------------------
AreaPOI.dbc is the client's own list of the named places drawn on the world map,
so taking it as the source means the pins are exactly the places the map already
labels - not a hand-kept list that drifts. Two of its fields classify them:

    Importance 3, Icon 6   the 8 capitals      Stormwind City, Orgrimmar, ...
    Importance 3, Icon 5   96 larger towns     Booty Bay, Astranaar, Garadar
    Importance 3, Icon 7   20 small villages   Goldshire, Brill, Razor Hill

Importance 0 holds another 232 rows - camps, towers, mines, single buildings.
They are left out: the map is a travel aid, and 356 pins is the wall of icons
this addon's continent view already had to be rescued from once.

Coordinates and the teleport
----------------------------
AreaPOI stores world coordinates. Both the pin and the teleport want zone
fractions instead, so both come from one conversion here:

    across = (world_y - y1) / (y2 - y1)
    down   = (world_x - x1) / (x2 - x1)

using the WorldMapArea.dbc bounds, the same form build_atlas_addon.py's
map_to_zone() uses. It is the exact inverse of the server's own
Zone2MapCoordinates(), which is what makes the teleport work: the addon sends
`.go zonexy <across*100> <down*100> <areaId>` and the server converts back
through the identical bounds, then snaps Z to the ground with GetHeight(). So no
height is ever guessed or shipped - which matters, because a POI's own Z is a
marker altitude, not the floor a player should land on.

A POI is placed on the map its own AreaID names, walked up AreaTable's parent
chain until an area with a WorldMapArea row is reached - Booty Bay's own
sub-area has no map, its parent Stranglethorn Vale does. That field, not
geometry, is what decides: zone boxes overlap generously, so "the smallest box
containing the point" puts Astranaar in Stonetalon Mountains and drops the
capitals onto the edge of their own city maps. AreaID agrees with the game
instead - Stormwind City is drawn on Elwynn Forest and Orgrimmar on Durotar,
which is where AreaID puts them.

Usage:
    build_towns_addon.py            # write to stdout
    build_towns_addon.py --write    # write addon/WorldforgedAtlas/Towns.lua
"""

import argparse
import sys
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2]
DBC_DIR = Path.home() / "azerothcore/env/dist/data/dbc"

sys.path.insert(0, str(MODULE / "tools/clientpatch"))

# AreaPOI.dbc field offsets, 3.3.5a.
POI_ICON = 2
POI_IMPORTANCE = 1
POI_X, POI_Y = 12, 13
POI_MAP = 15
POI_AREA = 17
POI_NAME = 18          # Name_lang, enUS

# Icon -> what the place is. Only these three, and only at importance 3, are
# settlements; every other icon is a tower, mine, gate or battleground marker.
RANKS = {6: 1, 5: 2, 7: 3}
RANK_NAMES = {1: "City", 2: "Town", 3: "Village"}


def load_areas():
    """area id -> its parent area, so a sub-area can be walked up to its zone."""
    from dbc import DBC

    at = DBC(str(DBC_DIR / "AreaTable.dbc"))
    return ({r[0]: at.s(r[11]) for r in at.rows()},
            {r[0]: r[2] for r in at.rows()})


def load_zones(area_names):
    """area id -> the zone map a pin can be placed on.

    A zone is only usable if it has a WorldMapArea row (bounds to convert
    through) and an AreaTable name (what GetMapZones() returns, and how the
    addon recognises the map now open). The key doubles as the argument
    `.go zonexy` wants, because the server indexes its own WorldMapArea store
    by exactly that field.
    """
    from dbc import DBC, F

    zones = {}
    wm = DBC(str(DBC_DIR / "WorldMapArea.dbc"))
    for r in wm.rows():
        area_id = r[2]
        y1, y2, x1, x2 = F(r[4]), F(r[5]), F(r[6]), F(r[7])

        # area_id 0 is a continent-wide row, which is not a zone map; a
        # zero-sized box would divide by zero.
        if not area_id or y1 == y2 or x1 == x2:
            continue

        name = area_names.get(area_id)
        if not name:
            continue

        zones[area_id] = {
            "area": area_id, "map": r[1], "zone": name, "texture": wm.s(r[3]),
            "y1": y1, "y2": y2, "x1": x1, "x2": x2,
        }

    return zones


def load_towns():
    from dbc import DBC, F

    poi = DBC(str(DBC_DIR / "AreaPOI.dbc"))
    towns = []
    for r in poi.rows():
        if r[POI_IMPORTANCE] != 3 or r[POI_ICON] not in RANKS:
            continue
        name = poi.s(r[POI_NAME])
        if not name:
            continue
        towns.append({
            "name": name, "rank": RANKS[r[POI_ICON]], "map": r[POI_MAP],
            "area": r[POI_AREA], "x": F(r[POI_X]), "y": F(r[POI_Y]),
        })
    return towns


def fractions(town, zone):
    across = (town["y"] - zone["y1"]) / (zone["y2"] - zone["y1"])
    down = (town["x"] - zone["x1"]) / (zone["x2"] - zone["x1"])
    return across, down


def by_area(town, zones, parents):
    """The map the town's own AreaID names, walked up to the first one with a map.

    The chain is finite in the DBC, but the bound keeps a malformed one from
    spinning forever. AreaID is 0xFFFFFFFF on the rows that have none.
    """
    area, hops = town["area"], 0
    while area and area != 0xFFFFFFFF and area not in zones and hops < 10:
        area = parents.get(area, 0)
        hops += 1
    return zones.get(area)


def by_geometry(town, zones):
    """The smallest zone box containing the town.

    Only a fallback. Zone boxes overlap, so on its own this misplaces anything
    near a border - but it is the only thing left for a row whose AreaID is
    unset (Dolanaar, Camp Winterhoof) or simply wrong (Camp Mojache claims
    Mulgore while standing in Feralas).
    """
    best, best_size = None, None
    for zone in zones.values():
        if zone["map"] != town["map"]:
            continue
        if not (min(zone["y1"], zone["y2"]) <= town["y"] <= max(zone["y1"], zone["y2"])):
            continue
        if not (min(zone["x1"], zone["x2"]) <= town["x"] <= max(zone["x1"], zone["x2"])):
            continue
        size = abs((zone["y2"] - zone["y1"]) * (zone["x2"] - zone["x1"]))
        if best_size is None or size < best_size:
            best, best_size = zone, size
    return best


def place(town, zones, parents):
    """The town's zone map and where it sits on it, plus how that was decided.

    AreaID first, and it has to land inside that zone's own box to be believed -
    a point outside means AreaPOI and WorldMapArea disagree, and then geometry
    is the better of the two answers.
    """
    zone = by_area(town, zones, parents)
    if zone is not None:
        across, down = fractions(town, zone)
        if 0.0 <= across <= 1.0 and 0.0 <= down <= 1.0:
            return zone, across, down, "area"

    zone = by_geometry(town, zones)
    if zone is None:
        return None, None, None, None

    across, down = fractions(town, zone)
    return zone, across, down, "geometry"


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_lua(zones, towns, dropped):
    out = []
    out.append("-- WorldforgedAtlas: every town and city, as a teleport target.\n")
    out.append("--\n")
    out.append("-- GENERATED by mod-madosa/tools/towns/build_towns_addon.py from the\n")
    out.append("-- client's AreaPOI.dbc and WorldMapArea.dbc - re-run the tool rather\n")
    out.append("-- than editing this file.\n")
    out.append("--\n")
    out.append(f"-- {len(towns)} places in {len(zones)} zones.\n")
    if dropped:
        out.append(f"-- {dropped} left out: no zone map box contains them.\n")
    out.append("--\n")
    out.append("-- Positions are zone-relative fractions, 0,0 at the map's top left, the\n")
    out.append("-- same form Data.lua uses. `area` is the AreaTable id `.go zonexy` takes,\n")
    out.append("-- and the fractions are what it converts back through - so the pin and the\n")
    out.append("-- teleport can never disagree about where a town is.\n")
    out.append("\n")
    out.append("local _, ns = ...\n\n")

    out.append("-- 1 city, 2 town, 3 village.\n")
    out.append("ns.townRanks = {\n")
    for rank in sorted(RANK_NAMES):
        out.append(f"    [{rank}] = {lua_string(RANK_NAMES[rank])},\n")
    out.append("}\n\n")

    out.append("-- index -> name, rank\n")
    out.append("ns.townInfo = {\n")
    for i, t in enumerate(towns, start=1):
        out.append(f"    [{i}] = {{{lua_string(t['name'])}, {t['rank']}}},\n")
    out.append("}\n\n")

    out.append("-- Flat triples: across, down, index into ns.townInfo. Flat for the same\n")
    out.append("-- reason Data.lua's are.\n")
    out.append("ns.towns = {\n")
    for z in zones:
        out.append(f"    {{zone = {lua_string(z['zone'])}, texture = {lua_string(z['texture'])}, "
                   f"area = {z['area']},\n")
        triples = []
        for i in range(0, len(z["points"]), 3):
            across, down, index = z["points"][i], z["points"][i + 1], z["points"][i + 2]
            triples.append(f"{across:.4f},{down:.4f},{index},")

        out.append("     points = {")
        for start in range(0, len(triples), 3):
            out.append("\n        " + " ".join(triples[start:start + 3]))
        out.append("\n    }},\n")
    out.append("}\n")

    return "".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="write addon/WorldforgedAtlas/Towns.lua")
    args = ap.parse_args()

    area_names, parents = load_areas()
    zones_by_area = load_zones(area_names)
    towns = load_towns()
    if not towns:
        raise SystemExit(f"no settlement rows in {DBC_DIR}/AreaPOI.dbc - "
                         "is the dbc directory the extracted one?")

    # Sorted by name so a regeneration produces a stable file, and so the index
    # a pin carries stays meaningful when read by hand.
    towns.sort(key=lambda t: (t["name"], t["map"], t["x"]))

    by_zone, dropped, fallback = {}, [], []
    for i, town in enumerate(towns, start=1):
        zone, across, down, how = place(town, zones_by_area, parents)
        if zone is None:
            dropped.append(f"{town['name']} (area {town['area']}, map {town['map']})")
            continue

        if how == "geometry":
            fallback.append(f"{town['name']} -> {zone['zone']}")

        z = by_zone.setdefault(zone["area"], {"zone": zone["zone"], "texture": zone["texture"],
                                              "area": zone["area"], "points": []})
        z["points"] += [across, down, i]

    if fallback:
        print(f"{len(fallback)} placed by geometry, their AreaID being unset or wrong: "
              + "; ".join(sorted(fallback)), file=sys.stderr)
    if dropped:
        print(f"{len(dropped)} left out, on no zone map at all: "
              + "; ".join(sorted(dropped)), file=sys.stderr)

    zones = sorted(by_zone.values(), key=lambda z: z["zone"])

    lua = build_lua(zones, towns, len(dropped))
    if args.write:
        out = MODULE / "addon/WorldforgedAtlas/Towns.lua"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(lua, encoding="utf-8")
        print(f"wrote {len(towns) - len(dropped)} places to {out}", file=sys.stderr)
    else:
        sys.stdout.write(lua)

    counts = {}
    for t in towns:
        counts[t["rank"]] = counts.get(t["rank"], 0) + 1
    plural = {1: "cities", 2: "towns", 3: "villages"}
    print(f"{len(zones)} zones, "
          + ", ".join(f"{counts.get(r, 0)} {plural[r]}" for r in sorted(plural)),
          file=sys.stderr)


if __name__ == "__main__":
    main()
