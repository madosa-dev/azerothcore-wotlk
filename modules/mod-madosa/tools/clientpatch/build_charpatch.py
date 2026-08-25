#!/usr/bin/env python3
"""Rebuild patch-enus-z.mpq - Ascension's character customization DBCs.

    python3 build_charpatch.py            # build into ./out
    python3 build_charpatch.py --install  # ... and copy into the client

This is the companion to build_patches.py (which does the pets). It takes the
four character DBCs out of Ascension's patch-M.MPQ and makes them safe for a
stock 3.3.5a client:

1. Drops every row for a race the client does not know. Ascension has race IDs
   up to 63; the stock client sizes its tables for 21 and writes past the end of
   a static array otherwise, which crashes it on startup with ERROR #132.

2. Fills in the SKIN_EXTRA texture. Ascension's character models declare a
   texture of type 8 (SKIN_EXTRA) for the ears and other add-on geometry, but
   their CharSections rows leave the second texture path empty - their patched
   client derives the "<skin>_Extra.blp" name itself. A stock client does not,
   so those geosets render untextured (white ears). The .blp files ship in
   patch-Q, so pointing the row at them is all that is needed.

Ascension's patch-M.MPQ also holds Spell.dbc, Item.dbc and the rest of their DBC
set. Never copy that archive wholesale - it would replace the client's entire
game data and break it against AzerothCore.
"""

import argparse
import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mpq import MPQ, build
from dbc import DBC, DBCBuilder
from build_patches import ASCENSION, CLIENT, LOCALE_DIR, OUT, client_dbc

# Which DBC, and which field holds the race id (CharacterFacialHairStyles has no
# id column, so its race sits at 0). BarberShopStyle keeps race far back at 37 -
# field 36 is the float cost multiplier, which is how the offset was confirmed.
DBCS = [
    ("CharSections.dbc", 1),
    ("CharHairGeosets.dbc", 1),
    ("CharacterFacialHairStyles.dbc", 0),
    ("BarberShopStyle.dbc", 37),
]

SECTION_SKIN = 0
F_BASE_SECTION, F_TEX0, F_TEX1, F_FLAGS = 3, 4, 5, 7


def known_races():
    """Race ids the client's own CharSections uses - our upper bound."""
    blob, source = client_dbc("CharSections.dbc")
    path = os.path.join(OUT, "_client_CharSections.dbc")
    open(path, "wb").write(blob)
    d = DBC(path)
    races = {r[1] for r in d.rows()}
    os.remove(path)
    return races, source, max(races)


def available_extras(archives=None):
    """Lowercased set of every *_Extra.blp the client can actually load.

    Scans data/ rather than naming archives, because the Ascension archives get
    demoted to other letters when build_earfix.py installs a model override.
    """
    if archives is None:
        data = os.path.join(CLIENT, "data")
        archives = [os.path.join(data, f) for f in sorted(os.listdir(data))
                    if f.lower().startswith("patch-") and f.lower().endswith(".mpq")]
    found = set()
    for path in archives:
        listing = MPQ(path).read_file("(listfile)")
        if not listing:
            continue
        for name in listing.decode("ascii", "replace").replace("\r\n", "\n").split("\n"):
            name = name.strip().lower()
            if name.endswith("_extra.blp"):
                found.add(name.replace("/", "\\"))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--no-extra", action="store_true",
                    help="do not link SKIN_EXTRA (ears stay untextured, but NPCs "
                         "that use a pre-baked texture keep their correct face)")
    ap.add_argument("--blank-baked", action="store_true",
                    help="also ship a CreatureDisplayInfoExtra.dbc with every baked "
                         "NPC texture cleared, so NPCs composite at runtime from "
                         "CharSections like players do. Pairs with SKIN_EXTRA; "
                         "touches ~13.7k rows, so try it before trusting it")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)

    if args.install and os.popen("pgrep -if 'wow\\.exe'").read().strip():
        raise SystemExit("The WoW client is running - close it first.")

    races, race_source, max_race = known_races()
    print(f"Client race ids from {race_source}: {len(races)} ids, highest {max_race}")

    extras = available_extras()
    print(f"_Extra textures available in the client: {len(extras)}")

    src = MPQ(os.path.join(ASCENSION, "patch-M.MPQ"))
    files = []
    for name, race_field in DBCS:
        raw = src.read_file("DBFilesClient\\" + name)
        tmp = os.path.join(OUT, "_asc_" + name)
        open(tmp, "wb").write(raw)
        b = DBCBuilder(tmp)

        before = len(b.rows)
        kept = [r for r in b.rows if r[race_field] in races]
        dropped = before - len(kept)

        linked = 0
        if name == "CharSections.dbc" and not args.no_extra:
            for row in kept:
                # Test the resolved string, not the offset: Ascension points every
                # unused texture slot at a shared empty string (offset 44), so a
                # non-zero offset here does not mean the slot is occupied.
                if row[F_BASE_SECTION] != SECTION_SKIN or b.src.s(row[F_TEX1]):
                    continue
                base = b.src.s(row[F_TEX0])
                if not base.lower().endswith(".blp"):
                    continue
                extra = base[:-4] + "_Extra.blp"
                if extra.lower().replace("/", "\\") in extras:
                    row[F_TEX1] = b.addstr(extra)
                    linked += 1

        b.rows = kept
        out = os.path.join(OUT, name)
        b.save(out)
        os.remove(tmp)
        note = f", {linked} SKIN_EXTRA textures linked" if linked else ""
        print(f"  {name:32} {before:>6} -> {len(kept):>6} rows ({dropped} custom-race{note})")
        files.append(("DBFilesClient\\" + name, open(out, "rb").read()))

    if args.blank_baked:
        blob, source = client_dbc("CreatureDisplayInfoExtra.dbc")
        tmp = os.path.join(OUT, "_asc_CreatureDisplayInfoExtra.dbc")
        open(tmp, "wb").write(blob)
        b = DBCBuilder(tmp)
        baked_field = b.src.fc - 1          # last column is the baked texture name
        cleared = 0
        for row in b.rows:
            if row[baked_field] and b.src.s(row[baked_field]):
                row[baked_field] = 0        # offset 0 is the empty string
                cleared += 1
        out = os.path.join(OUT, "CreatureDisplayInfoExtra.dbc")
        b.save(out)
        os.remove(tmp)
        print(f"  {'CreatureDisplayInfoExtra.dbc':32} {cleared} baked textures cleared "
              f"(base {source})")
        files.append(("DBFilesClient\\CreatureDisplayInfoExtra.dbc", open(out, "rb").read()))

    size, _ = build(os.path.join(OUT, "patch-enus-z.mpq"), files)
    print(f"patch-enus-z.mpq  {size / 1024 / 1024:6.1f} MB  ({len(files)} DBCs)")

    m = MPQ(os.path.join(OUT, "patch-enus-z.mpq"))
    bad = [n for n, blob in files if m.read_file(n) != blob]
    if bad:
        raise SystemExit(f"round-trip failed for {bad}")
    print("Round-trip verified.")

    if args.install:
        shutil.copy(os.path.join(OUT, "patch-enus-z.mpq"),
                    os.path.join(LOCALE_DIR, "patch-enus-z.mpq"))
        wdb = os.path.join(CLIENT, "Cache/WDB/enUS")
        for f in os.listdir(wdb) if os.path.isdir(wdb) else []:
            if f.endswith(".wdb"):
                os.remove(os.path.join(wdb, f))
        print("Installed. Restart the client.")
    else:
        print(f"Wrote {OUT}. Re-run with --install to deploy.")


if __name__ == "__main__":
    main()
