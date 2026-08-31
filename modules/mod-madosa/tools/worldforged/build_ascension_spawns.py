#!/usr/bin/env python3
"""Turn Ascension's Worldforged find locations into spawn points.

    python3 build_ascension_spawns.py            # print the SQL
    python3 build_ascension_spawns.py --write    # write it into data/sql/db-world/base/

Where the data comes from
-------------------------
The `LootCollector` addon in the Ascension client - a community effort that
records where players find Worldforged items and shares it. Its starter database
ships 4524 discoveries as one compressed blob:

    "!LC1!" + LibDeflate:EncodeForPrint( deflate( AceSerializer:Serialize(t) ) )

so this tool re-implements that pipeline backwards (the 6-bit print alphabet,
raw inflate, then the AceSerializer text format) to get at the table.

Coordinates
-----------
LootCollector stores zone-relative percentages, which are turned into world
coordinates the same way the core's own Zone2MapCoordinates() does it
(DBCStores.cpp:771), axis swap included, using WorldMapArea.dbc keyed by area id.

That conversion is worth checking rather than trusting, and it checks out: the
median converted point lands 16 yards from the nearest creature spawn in this
world database, and 87% land within 50 yards. Wrong coordinates would scatter
into the ocean.

Locations in caves, mines and starting sub-zones are dropped: their percentages
are relative to a sub-map that has no WorldMapArea row, so they cannot be
converted. That is ~9% of the finds.

No Z coordinate
---------------
Ground height needs the server's map data, so it is resolved at run time with
Map::GetHeight() when a cache is streamed in - see mod_madosa_worldforged_ascension.cpp.
"""

import argparse
import json
import re
import struct
import sys
import zlib
from pathlib import Path

HOME = Path.home()
ASC = HOME / "Games/ascension-wow2/drive_c/Program Files/Ascension Launcher/resources/ascension-live"
STARTER_DB = ASC / "Interface/AddOns/LootCollector.repo/LootCollector_StarterDB/db.lua"
ZONE_LIST = ASC / "Interface/AddOns/LootCollector.repo/LootCollector/Modules/ZoneList.lua"
DBC_DIR = HOME / "azerothcore/env/dist/data/dbc"

sys.path.insert(0, str(HOME / "azerothcore/modules/mod-madosa/tools/clientpatch"))

DISCOVERY_WORLDFORGED = 1

# Two finds of the same item closer together than this are the same chest, seen
# by two different players. Generous, because LootCollector stores where the
# *finder stood*, not where the object was.
MERGE_DISTANCE = 40.0
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
ALPHABET_INDEX = {c: i for i, c in enumerate(ALPHABET)}


# --------------------------------------------------------------------------
# LootCollector's export format
# --------------------------------------------------------------------------

def decode_for_print(s):
    """Inverse of LibDeflate:EncodeForPrint - 6 bits per character, little-endian."""
    out, cache, bits = bytearray(), 0, 0
    for ch in s:
        v = ALPHABET_INDEX.get(ch)
        if v is None:
            continue
        cache |= v << bits
        bits += 6
        while bits >= 8:
            out.append(cache & 0xFF)
            cache >>= 8
            bits -= 8
    return bytes(out)


def unescape(s):
    """Inverse of AceSerializer's SerializeStringHelper."""
    special = {"z": "\x1e", "{": "\x7f", "|": "~", "}": "^"}
    return re.sub(r"~.", lambda m: special.get(m.group(0)[1], chr(ord(m.group(0)[1]) - 64)), s)


class AceDeserializer:
    def __init__(self, text):
        self.t = text.split("^")
        if self.t[0] != "" or self.t[1] != "1":
            raise SystemExit("not an AceSerializer v1 stream")
        self.i = 2

    def value(self):
        tag = self.t[self.i]; self.i += 1
        kind, rest = tag[0], tag[1:]
        if kind == "S":
            return unescape(rest)
        if kind == "N":
            return float(rest) if ("." in rest or "e" in rest.lower()) else int(rest)
        if kind == "F":
            mantissa = int(rest)
            exp = self.t[self.i]; self.i += 1
            return mantissa * 2.0 ** int(exp[1:])
        if kind == "B":
            return True
        if kind == "b":
            return False
        if kind == "Z":
            return None
        if kind == "T":
            out = {}
            while self.t[self.i][0] != "t":
                k = self.value()
                out[k] = self.value()
            self.i += 1
            return out
        raise SystemExit(f"unknown AceSerializer tag {tag!r}")


def load_discoveries(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'data\s*=\s*"!LC1!([^"]+)"', text, re.S)
    if not m:
        raise SystemExit(f"no !LC1! payload in {path}")
    plain = zlib.decompress(decode_for_print(m.group(1)), -15).decode("utf-8", "replace")
    return AceDeserializer(plain).value()["discoveries"]


# --------------------------------------------------------------------------
# Coordinates
# --------------------------------------------------------------------------

def load_zone_names(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    return {int(m.group(1)): m.group(2)
            for m in re.finditer(r'\[(\d+)\]\s*=\s*\{\s*name\s*=\s*"([^"]+)"', text)}


def load_dbc_tables():
    from dbc import DBC

    def as_float(u):
        return struct.unpack("<f", struct.pack("<I", u & 0xFFFFFFFF))[0]

    areas = {}
    at = DBC(str(DBC_DIR / "AreaTable.dbc"))
    for r in at.rows():
        name = at.s(r[11])
        if name:
            areas.setdefault(name, r[0])

    wma = {}
    for r in DBC(str(DBC_DIR / "WorldMapArea.dbc")).rows():
        wma[r[2]] = {
            "map_id": r[1],
            "y1": as_float(r[4]), "y2": as_float(r[5]),
            "x1": as_float(r[6]), "x2": as_float(r[7]),
            "virtual_map_id": r[8] if r[8] != 0xFFFFFFFF else -1,
        }
    return areas, wma


def zone_to_map(x_pct, y_pct, e):
    """Zone percentages (0..1) to map coordinates - note the axis swap, as in the core."""
    x, y = y_pct * 100.0, x_pct * 100.0
    return (x * ((e["x2"] - e["x1"]) / 100.0) + e["x1"],
            y * ((e["y2"] - e["y1"]) / 100.0) + e["y1"])


# --------------------------------------------------------------------------

def esc(s):
    return s.replace("\\", "\\\\").replace("'", "''")


def build_sql(points, dropped_zones):
    rows = ",\n".join(
        "({}, {}, {:.4f}, {:.4f}, {}, '{}')".format(i, p["map"], p["x"], p["y"], p["item"], esc(p["zone"]))
        for i, p in enumerate(points, start=1))
    return (
        "-- Ascension's Worldforged find locations.\n"
        "--\n"
        "-- The table is created by worldforged.sql, which the DB updater applies first\n"
        "-- because it sorts module SQL by filename and '.' sorts before '_'.\n"
        "--\n"
        "-- GENERATED by tools/worldforged/build_ascension_spawns.py - re-run the tool\n"
        "-- rather than editing this file.\n"
        "--\n"
        "-- Decoded from the LootCollector addon's community starter database in the\n"
        "-- Ascension client and converted from zone percentages to world coordinates the\n"
        "-- same way the core's Zone2MapCoordinates() does. Verified against this world\n"
        "-- database: the median point lands 16 yards from the nearest creature spawn.\n"
        "--\n"
        "-- Several players finding the same chest each produced their own recording,\n"
        "-- so entries of the same item within a few yards are merged into one -\n"
        "-- otherwise the world gets three chests side by side where Ascension has one.\n"
        "--\n"
        "-- `item` is the Worldforged item Ascension players actually found at that spot.\n"
        "-- There is no Z: ground height needs the server's map data and is resolved with\n"
        "-- Map::GetHeight() when the cache is streamed in.\n"
        "--\n"
        f"-- {len(points)} locations. {dropped_zones} finds were dropped: they sit in caves,\n"
        "-- mines and starting sub-zones, whose percentages are relative to a sub-map with\n"
        "-- no WorldMapArea row and so cannot be converted.\n"
        "\n"
        "DELETE FROM `mod_madosa_worldforged_ascension_spawns`;\n"
        "INSERT INTO `mod_madosa_worldforged_ascension_spawns`\n"
        "  (`id`, `map`, `position_x`, `position_y`, `item`, `zone`) VALUES\n"
        f"{rows};\n"
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="write data/sql/db-world/base/worldforged_ascension_spawns.sql")
    args = ap.parse_args()

    discoveries = load_discoveries(STARTER_DB)
    zone_names = load_zone_names(ZONE_LIST)
    areas, wma = load_dbc_tables()

    points, dropped = [], 0
    for d in discoveries.values():
        if d.get("discoveryType") != DISCOVERY_WORLDFORGED:
            continue
        zone = zone_names.get(d["zoneID"])
        entry = wma.get(areas.get(zone, -1)) if zone else None
        if not entry:
            dropped += 1
            continue
        x, y = zone_to_map(d["coords"]["x"], d["coords"]["y"], entry)
        points.append({
            "map": entry["virtual_map_id"] if entry["virtual_map_id"] >= 0 else entry["map_id"],
            "x": x, "y": y, "item": d["itemID"], "zone": zone,
        })

    # LootCollector records a find per player, so one physical Ascension spot
    # shows up several times a few yards apart - three "Claw of Vagash" entries
    # within ten yards of each other are one chest, recorded by three people.
    # Collapse each cluster of the same item into a single point, or the world
    # ends up with duplicate chests standing side by side.
    points.sort(key=lambda p: (p["item"], p["map"], p["x"], p["y"]))
    merged, duplicates = [], 0
    for point in points:
        near = next((k for k in reversed(merged)
                     if k["item"] == point["item"] and k["map"] == point["map"]
                     and (k["x"] - point["x"]) ** 2 + (k["y"] - point["y"]) ** 2 <= MERGE_DISTANCE ** 2), None)
        if near:
            duplicates += 1
            continue
        merged.append(point)
    points = merged
    print(f"{duplicates} duplicate recordings of the same spot merged away", file=sys.stderr)

    # Sorted so a regeneration produces a stable file instead of hash-order churn.
    points.sort(key=lambda p: (p["map"], round(p["x"], 4), round(p["y"], 4), p["item"]))

    sql = build_sql(points, dropped)
    if args.write:
        out = Path(__file__).resolve().parents[2] / "data/sql/db-world/base/worldforged_ascension_spawns.sql"
        out.write_text(sql, encoding="utf-8")
        print(f"wrote {len(points)} locations to {out}", file=sys.stderr)
    else:
        sys.stdout.write(sql)

    print(f"{len(points)} locations converted, {dropped} unconvertible, "
          f"{len({p['item'] for p in points})} distinct items", file=sys.stderr)


if __name__ == "__main__":
    main()
