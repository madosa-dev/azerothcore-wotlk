#!/usr/bin/env python3
"""Import the spells behind Ascension's Worldforged item effects.

    python3 build_ascension_spells.py            # print the SQL
    python3 build_ascension_spells.py --write    # write it into data/sql/db-world/base/

The effects are what make a Worldforged item more than its stat line - a ring
that instils fear, a shield that retaliates with nature damage. The items
reference 586 distinct spells; 5 of those are ordinary WotLK spells this server
already has, and the other 581 are Ascension's own.

Where they come from
--------------------
Ascension's own Spell.dbc, which lives in `patch-T.MPQ` (not a locale archive,
where you would look first). It is 209 MB against this client's 49 MB - 209294
spells against 49840 - but the layout is untouched: 234 fields, 936 bytes a row,
exactly like WotLK's. So a spell can be carried over as a straight row copy, and
all 581 are in there.

Why this goes into spell_dbc rather than a patched file
------------------------------------------------------
DBCStores loads Spell.dbc and then overlays the world DB's `spell_dbc` table on
top (DBCStores.cpp:371), and the store's index table grows to fit ids beyond the
file's own maximum. So a row here is all the server needs to know a new spell -
no patched Spell.dbc on the server side, and the import stays versioned SQL like
everything else. (The *client* still needs its own Spell.dbc row for the tooltip;
that is what build_client_patch.py handles.)

What gets clamped, and why it must be
-------------------------------------
Ascension extended the spell system: among these 581 spells the effect ids reach
183 and the aura ids reach 354, where WotLK stops at 164 and 316. Those are not
merely unknown to this core - `AuraEffect::HandleEffect` indexes a fixed
`AuraEffectHandler[TOTAL_AURAS]` array with the aura id and performs no bounds
check (SpellAuraEffects.cpp:793), so an aura id of 354 would call whatever lies
past the end of that array. Any effect or aura id outside WotLK's range is
therefore zeroed on import. That costs 22 of the 581 spells their custom
behaviour; the other 559 use nothing but stock WotLK effects and auras, and work
on this server exactly as they did on Ascension.
"""

import argparse
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
ASCENSION_DATA = (HOME / "Games/ascension-wow2/drive_c/Program Files/Ascension Launcher"
                         "/resources/ascension-live/Data")
ITEM_CACHE = (HOME / "Games/ascension-wow2/drive_c/Program Files/Ascension Launcher/resources"
                     "/ascension-live/Cache/WDB/enUS/Rexxar - Conquest of Azeroth/itemcache.wdb")
SERVER_DBC = HOME / "azerothcore/env/dist/data/dbc"
CONF = HOME / "azerothcore/env/dist/etc/worldserver.conf"

sys.path.insert(0, str(HOME / "azerothcore/modules/mod-madosa/tools/clientpatch"))
from dbc import DBC                     # noqa: E402
from mpq import MPQ                     # noqa: E402

CACHE_DIR = Path(__file__).resolve().parent / "out"

# WotLK's own limits. SharedDefines.h: TOTAL_SPELL_EFFECTS = 165, so the highest
# valid effect is 164. SpellAuraDefines.h: TOTAL_AURAS = 317, highest aura 316.
MAX_EFFECT = 164
MAX_AURA = 316

# Spell.dbc field indices, 0-based, the same numbering clientpatch verified.
F_CATEGORY = 1
F_EFFECT = (71, 72, 73)
F_EFFECT_AURA = (95, 96, 97)
F_SPELL_ICON, F_ACTIVE_ICON = 133, 134
F_NAME = 136

# Spells reached from another spell rather than from an item. "Fiery Attack"
# says "every 10th attack triggers a fiery attack dealing N fire damage" and does
# it by casting a second spell; import only the first and the proc fires into
# nothing. So the import follows these references until the set closes.
F_EFFECT_TRIGGER = (116, 117, 118)
F_CASTER_AURA_SPELL, F_TARGET_AURA_SPELL = 24, 25


def parse_db_info(key):
    text = CONF.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    if not m:
        raise SystemExit(f"could not find {key} in {CONF}")
    host, port, user, password, database = m.group(1).split(";")
    return dict(host=host, port=port, user=user, password=password, database=database)


def query(sql):
    info = parse_db_info("WorldDatabaseInfo")
    proc = subprocess.run(
        ["mysql", f"-h{info['host']}", f"-P{info['port']}", f"-u{info['user']}", "-N", "-B", info["database"]],
        input=sql, env={"MYSQL_PWD": info["password"]}, capture_output=True, text=True, timeout=60)
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.strip())
    return [line.split("\t") for line in proc.stdout.splitlines() if line]


def spell_dbc_columns():
    """The table's columns in order, so field index N maps to column N."""
    # COLUMN_TYPE, not DATA_TYPE: 115 of these columns are `int unsigned` and hold
    # bitmasks with the top bit set. Writing those through a signed conversion
    # makes MySQL reject the row outright ("out of range value"), so signedness
    # has to come from the schema rather than being assumed.
    rows = query("SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE FROM information_schema.columns "
                 "WHERE table_name = 'spell_dbc' AND table_schema = DATABASE() "
                 "ORDER BY ORDINAL_POSITION;")
    if len(rows) != 234:
        raise SystemExit(f"spell_dbc has {len(rows)} columns, expected 234 - schema mismatch")
    return [(name, kind, "unsigned" in column_type) for name, kind, column_type in rows]


def ascension_spell_dbc():
    """Ascension's Spell.dbc, cached locally - it is 209 MB and slow to pull."""
    cached = CACHE_DIR / "ascension_Spell.dbc"
    if cached.exists():
        return cached

    CACHE_DIR.mkdir(exist_ok=True)
    biggest = None
    for directory in (ASCENSION_DATA, ASCENSION_DATA / "enUS"):
        for name in sorted(os.listdir(directory)):
            if not name.lower().endswith(".mpq"):
                continue
            try:
                blob = MPQ(str(directory / name)).read_file("DBFilesClient\\Spell.dbc")
            except Exception:
                continue
            if blob and (biggest is None or len(blob) > len(biggest)):
                biggest = blob
    if not biggest:
        raise SystemExit("no readable Spell.dbc in the Ascension archives")

    cached.write_bytes(biggest)
    return cached


def worldforged_spell_ids():
    """Every spell the Worldforged items reference."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from build_ascension_items import read_cache, WORLDFORGED_TAG, located_items

    keep = set()
    located = located_items()
    for item in read_cache(ITEM_CACHE):
        if WORLDFORGED_TAG in (item["description"] or "") or item["entry"] in located:
            for spell in item["spells"]:
                if spell[0] > 0:
                    keep.add(spell[0])
    return keep


def as_float(value):
    return struct.unpack("<f", struct.pack("<I", value & 0xFFFFFFFF))[0]


def as_signed(value):
    return struct.unpack("<i", struct.pack("<I", value & 0xFFFFFFFF))[0]


def esc(text):
    """SQL-escape, with newlines written as escapes rather than left literal.

    Ascension's spell descriptions carry CR and LF. Emitting those raw puts real
    line breaks inside the generated file's string literals, which git then
    rewrites on checkout - and a file that changes shape makes the DB updater
    re-apply it on every start.
    """
    return (text.replace("\\", "\\\\").replace("'", "''")
                .replace("\r", "\\r").replace("\n", "\\n"))


def safe_string(dbc, offset):
    """dbc.s() with bounds checks.

    A few rows in Ascension's Spell.dbc carry a string offset that points past
    the end of the string block - harmless in the client, which never reads those
    slots, but dbc.s() walks off the end looking for a terminator. Treat anything
    unreadable as empty rather than letting one bad offset stop the import.
    """
    if not offset or offset >= dbc.sb:
        return ""

    start = dbc.sblock + offset
    end = dbc.d.find(b"\0", start, dbc.sblock + dbc.sb)
    if end < 0:
        return ""
    return dbc.d[start:end].decode("utf-8", "replace")


def select_spells(quiet=False):
    """The spells to import, already clamped, keyed by id.

    Shared by this tool and the client patch: both sides must agree on exactly
    which spells exist and on what their effects are, or the tooltip would
    describe behaviour the server does not perform.

    Returns (rows, ascension_dbc). Rows are plain lists so callers can write
    them either into SQL or straight back into a DBC.
    """
    def say(*a):
        if not quiet:
            print(*a, file=sys.stderr)

    have = {r[0] for r in DBC(str(SERVER_DBC / "Spell.dbc")).rows()}
    categories = {r[0] for r in DBC(str(SERVER_DBC / "SpellCategory.dbc")).rows()}

    wanted = worldforged_spell_ids()
    missing = wanted - have
    say(f"Worldforged items reference {len(wanted)} spells; {len(wanted) - len(missing)} already exist here")

    asc = DBC(str(ascension_spell_dbc()))
    say(f"Ascension Spell.dbc: {asc.rc} rows, {asc.fc} fields")
    if asc.fc != 234:
        raise SystemExit(f"Ascension Spell.dbc has {asc.fc} fields, expected 234 - cannot copy rows")

    # Index once: the closure below needs random access, and re-scanning 209294
    # rows per lookup would take longer than the rest of the tool put together.
    by_id = {r[0]: r for r in asc.rows()}

    # Follow every spell a wanted spell casts, and everything those cast in turn,
    # until nothing new turns up. Without this an effect like "Fiery Attack"
    # imports as a proc that triggers a spell nothing has ever heard of.
    closed, frontier = set(missing), set(missing)
    while frontier:
        nxt = set()
        for sid in frontier:
            row = by_id.get(sid)
            if not row:
                continue
            for i in F_EFFECT_TRIGGER + (F_CASTER_AURA_SPELL, F_TARGET_AURA_SPELL):
                ref = row[i]
                if ref and ref not in have and ref not in closed:
                    nxt.add(ref)
        closed |= nxt
        frontier = nxt

    say(f"  followed {len(closed) - len(missing)} further spell(s) referenced by those")

    absent = sorted(closed - set(by_id))
    if absent:
        say(f"  WARNING: {len(absent)} not in Ascension's DBC either: {absent[:8]}")

    rows = {}
    effects = auras = cats = 0
    for sid in sorted(closed & set(by_id)):
        row = list(by_id[sid])
        for i in F_EFFECT:
            if row[i] > MAX_EFFECT:
                row[i] = 0
                effects += 1
        for i in F_EFFECT_AURA:
            if row[i] > MAX_AURA:
                row[i] = 0
                auras += 1
        if row[F_CATEGORY] and row[F_CATEGORY] not in categories:
            row[F_CATEGORY] = 0
            cats += 1
        rows[sid] = row

    say(f"  clamped {effects} out-of-range effect(s), {auras} aura(s), {cats} category reference(s)")
    return rows, asc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="write data/sql/db-world/base/worldforged_ascension_spells.sql")
    args = ap.parse_args()

    columns = spell_dbc_columns()
    rows, asc = select_spells()

    values = []
    for sid in sorted(rows):
        src = rows[sid]
        cells = []
        for i, (name, kind, unsigned) in enumerate(columns):
            raw = src[i]
            if kind == "float":
                cells.append(f"{as_float(raw):g}")
            elif kind in ("varchar", "text"):
                cells.append(f"'{esc(safe_string(asc, raw))}'")
            elif unsigned:
                cells.append(str(raw & 0xFFFFFFFF))
            else:
                cells.append(str(as_signed(raw)))
        values.append("(" + ",".join(cells) + ")")

    column_list = ",".join(f"`{name}`" for name, _, _ in columns)
    sql = (
        "-- The spells behind Ascension's Worldforged item effects.\n"
        "--\n"
        "-- GENERATED by tools/worldforged/build_ascension_spells.py - re-run the tool\n"
        "-- rather than editing this file. See its docstring for where the data comes\n"
        "-- from and why anything is changed on the way in.\n"
        "--\n"
        "-- These go into spell_dbc rather than a patched Spell.dbc because DBCStores\n"
        "-- overlays that table on top of the file and grows its index table to fit ids\n"
        "-- past the file's maximum - so a row here is all the server needs to know a\n"
        "-- new spell. The client needs its own Spell.dbc row for the tooltip; that is\n"
        "-- what tools/worldforged/build_client_patch.py supplies.\n"
        "--\n"
        "-- Effect ids above 164 and aura ids above 316 are zeroed on import. That is not\n"
        "-- tidiness: AuraEffect::HandleEffect indexes a fixed AuraEffectHandler[317]\n"
        "-- array with the aura id and bounds-checks nothing, so a stray 354 would call\n"
        "-- past the end of it.\n"
        "--\n"
        f"-- {len(values)} spells.\n"
        "\n"
        "DELETE FROM `spell_dbc` WHERE `ID` IN (SELECT `spell` FROM `mod_madosa_worldforged_ascension_spells`);\n"
        "DELETE FROM `mod_madosa_worldforged_ascension_spells`;\n"
        "INSERT INTO `mod_madosa_worldforged_ascension_spells` (`spell`) VALUES\n"
        + ",\n".join(f"({sid})" for sid in sorted(rows)) + ";\n"
        "\n"
        f"INSERT INTO `spell_dbc` ({column_list}) VALUES\n"
        + ",\n".join(values) + ";\n"
    )

    if args.write:
        out = Path(__file__).resolve().parents[2] / "data/sql/db-world/base/worldforged_ascension_spells.sql"
        out.write_text(sql, encoding="utf-8")
        print(f"wrote {len(values)} spells to {out}", file=sys.stderr)
    else:
        sys.stdout.write(sql)


if __name__ == "__main__":
    main()
