#!/usr/bin/env python3
"""Regenerate the Worldforged Cache spawn points from the live world database.

    python3 build_spawns.py            # print the SQL
    python3 build_spawns.py --write    # ... and write it into data/sql/db-world/base/

Why the positions come from creature spawns
-------------------------------------------
A cache needs a position that is on solid ground, reachable on foot, out in the
world rather than inside a city, and it needs a level so the forge can pick a
spot that suits whoever is online. A world creature spawn answers all of that at
once and exactly: the position is one the server already spawns something at,
and the creature's own template carries the level. Deriving it from the
`gameobject` table instead would have meant guessing a level, and neither table's
`zoneId` column is usable here - it is populated for only ~40% of gameobject and
~3% of creature rows in this database.

The candidate filter keeps "wild mobs standing out in the world":

    rank = 0            no elites, rares or bosses - their spots are set pieces
    npcflag = 0         drops every vendor, trainer, questgiver, flightmaster,
                        i.e. essentially every city and camp NPC
    flags_extra & 128   excludes invisible trigger creatures, which are spawned
                        in places a player can neither reach nor see
    faction not in      excludes the neutral/friendly critter factions, whose
    (35, 31, 7, 12)     spawns cluster inside towns
    lootid <> 0         the creature drops something when killed, i.e. it is a
                        mob you fight rather than someone standing in a city -
                        a sharper filter than the faction list alone, because a
                        town guard can carry an ordinary hostile-looking faction
    map in              the four open-world continents; everything else is an
    (0, 1, 530, 571)    instance, a battleground or a test map

Spread
------
Candidates are bucketed into five-level bands and, within each band, accepted
greedily only when at least MIN_DISTANCE yards from every point already accepted
on that map. That turns ~80k clustered candidates into a couple hundred spots
scattered across the world instead of a dozen mob camps. The RNG is seeded, so
re-running this produces the same file unless the database itself changed.
"""

import argparse
import math
import random
import re
import subprocess
import sys
from pathlib import Path

# Points accepted per five-level band, and how far apart they must be (yards).
POINTS_PER_BAND = 12
MIN_DISTANCE = 400.0
BAND_SIZE = 5
MAX_LEVEL = 80
SEED = 20260831

MAP_NAMES = {0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland", 571: "Northrend"}

CANDIDATE_QUERY = """
SELECT c.map, c.position_x, c.position_y, c.position_z, c.orientation,
       ct.minlevel, ct.maxlevel, ct.name
FROM creature c
JOIN creature_template ct ON ct.entry = c.id
WHERE c.map IN (0, 1, 530, 571)
  AND c.phaseMask = 1
  AND ct.rank = 0
  AND ct.npcflag = 0
  AND (ct.flags_extra & 128) = 0
  AND ct.minlevel BETWEEN 1 AND 80
  AND ct.maxlevel BETWEEN 1 AND 80
  AND ct.faction NOT IN (35, 31, 7, 12)
  AND ct.lootid <> 0
"""


def find_default_conf() -> Path:
    # tools/worldforged/build_spawns.py -> modules/mod-madosa -> modules -> repo root
    repo_root = Path(__file__).resolve().parents[4]
    return repo_root / "env" / "dist" / "etc" / "worldserver.conf"


def parse_db_info(conf_path: Path, key: str) -> dict:
    text = conf_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    if not m:
        raise SystemExit(f"Could not find {key} in {conf_path}")
    host, port, user, password, database = m.group(1).split(";")
    return {"host": host, "port": port, "user": user, "password": password, "database": database}


def query(sql: str, info: dict) -> list:
    proc = subprocess.run(
        ["mysql", f"-h{info['host']}", f"-P{info['port']}", f"-u{info['user']}", "-N", "-B", info["database"]],
        input=sql,
        env={"MYSQL_PWD": info["password"]},
        capture_output=True,
        text=True,
        timeout=120,
    )
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.strip())
    return [line.split("\t") for line in proc.stdout.splitlines() if line]


def band_of(min_level: int, max_level: int) -> int:
    """Five-level band index for a creature, from the midpoint of its level range."""
    mid = (min_level + max_level) // 2
    return min(mid, MAX_LEVEL - 1) // BAND_SIZE


def pick_spread(candidates: list) -> list:
    """Greedily accept candidates that are far enough from everything already taken."""
    rng = random.Random(SEED)
    rng.shuffle(candidates)

    accepted = []
    taken_per_map = {}
    per_band = {}
    min_distance_sq = MIN_DISTANCE * MIN_DISTANCE

    for cand in candidates:
        band = cand["band"]
        if per_band.get(band, 0) >= POINTS_PER_BAND:
            continue

        taken = taken_per_map.setdefault(cand["map"], [])
        if any((cand["x"] - x) ** 2 + (cand["y"] - y) ** 2 < min_distance_sq for x, y in taken):
            continue

        taken.append((cand["x"], cand["y"]))
        per_band[band] = per_band.get(band, 0) + 1
        accepted.append(cand)

    # Ordered by level so the generated file reads like a progression, and so a
    # diff after a regeneration stays local to the bands that actually changed.
    accepted.sort(key=lambda c: (c["min_level"], c["map"], c["x"]))
    return accepted


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("'", "''")


def build_sql(points: list) -> str:
    lines = []
    for i, p in enumerate(points, start=1):
        comment = f"{MAP_NAMES.get(p['map'], p['map'])}: near {p['name']}"
        lines.append(
            "({}, {}, {:.4f}, {:.4f}, {:.4f}, {:.4f}, {}, {}, '{}')".format(
                i, p["map"], p["x"], p["y"], p["z"], p["o"],
                p["min_level"], p["max_level"], escape(comment),
            )
        )

    body = ",\n".join(lines)
    return (
        "-- Worldforged Cache spawn points.\n"
        "--\n"
        "-- The table itself is created by worldforged.sql, which the DB updater applies\n"
        "-- first because it sorts module SQL by filename and '.' sorts before '_'.\n"
        "--\n"
        "-- GENERATED by tools/worldforged/build_spawns.py - do not hand-edit this block;\n"
        "-- re-run the tool instead. Hand-picked spots of your own belong in a separate\n"
        "-- INSERT with ids from 10000 up, which regeneration leaves alone.\n"
        "--\n"
        "-- Each row is a position taken from a real world creature spawn, so it is on\n"
        "-- reachable ground out in the world, and min_level/max_level are that\n"
        "-- creature's own levels - which is what the forge matches against the levels of\n"
        f"-- the real players currently online. {len(points)} points, spread across every\n"
        f"-- five-level band and at least {MIN_DISTANCE:.0f} yards apart within a map.\n"
        "\n"
        "DELETE FROM `mod_madosa_worldforged_spawns` WHERE `id` < 10000;\n"
        "INSERT INTO `mod_madosa_worldforged_spawns`\n"
        "  (`id`, `map`, `position_x`, `position_y`, `position_z`, `orientation`, `min_level`, `max_level`, `comment`) VALUES\n"
        f"{body};\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--conf", type=Path, default=None, help="path to worldserver.conf (default: auto-detect)")
    parser.add_argument("--write", action="store_true", help="write data/sql/db-world/base/worldforged_spawns.sql")
    args = parser.parse_args()

    conf = args.conf or find_default_conf()
    rows = query(CANDIDATE_QUERY, parse_db_info(conf, "WorldDatabaseInfo"))
    if not rows:
        raise SystemExit("no candidate creature spawns found - is the world database populated?")

    candidates = []
    for map_id, x, y, z, o, min_level, max_level, name in rows:
        min_level, max_level = int(min_level), int(max_level)
        candidates.append({
            "map": int(map_id),
            "x": float(x), "y": float(y), "z": float(z), "o": float(o),
            "min_level": min_level, "max_level": max_level,
            "band": band_of(min_level, max_level),
            "name": name,
        })

    points = pick_spread(candidates)
    sql = build_sql(points)

    if args.write:
        out = Path(__file__).resolve().parents[2] / "data" / "sql" / "db-world" / "base" / "worldforged_spawns.sql"
        out.write_text(sql, encoding="utf-8")
        print(f"wrote {len(points)} spawn points to {out}", file=sys.stderr)
    else:
        sys.stdout.write(sql)

    bands = {}
    for p in points:
        bands[band_of(p["min_level"], p["max_level"])] = bands.get(band_of(p["min_level"], p["max_level"]), 0) + 1
    summary = ", ".join(f"{b * BAND_SIZE + 1}-{(b + 1) * BAND_SIZE}: {n}" for b, n in sorted(bands.items()))
    print(f"{len(points)} points from {len(candidates)} candidates ({summary})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
