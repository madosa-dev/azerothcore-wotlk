#!/usr/bin/env python3
"""Make Ascension's character models take their ear texture from the body skin.

    python3 build_earfix.py                 # dwarf male only, into ./out
    python3 build_earfix.py --all           # all base-race models
    python3 build_earfix.py --all --install # ... and deploy

The problem: Ascension's character models declare a texture of type 8
(SKIN_EXTRA) for the head mesh, which includes the ears. A stock 3.3.5a client
has no source for that texture, so the ears render white.

Filling it in through CharSections works for players but breaks the ~13.7k NPCs
that use a pre-baked texture, and blanking those bakes crashes the client (6340
of them reference a face or beard that has no CharSections row at all - the bake
is their only appearance source). See build_charpatch.py --blank-baked.

This takes the other route and touches no DBC at all: rewrite the texture's type
from 8 (SKIN_EXTRA) to 1 (SKIN) inside the .m2, so the ear samples the ordinary
body skin - which does carry an ear in its atlas. Whether the UVs line up is the
open question, hence the single-model default.

Layout note: the patched models must outrank Ascension's own archive, and
Ascension's sits at the highest letter. deploy() therefore demotes them first -
patch-y (CHA) -> patch-o, patch-z (Q) -> patch-p - which is safe because no
archive between patch-f and patch-y carries any Character\\ file.
"""

import argparse
import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mpq import MPQ, build
from build_patches import CLIENT, OUT

DATA = os.path.join(CLIENT, "data")

TEX_SKIN, TEX_SKIN_EXTRA = 1, 8

RACES = [("Dwarf", "Male")]
ALL_RACES = [(r, g) for r in ("Human", "Orc", "Dwarf", "NightElf", "Scourge",
                              "Tauren", "Gnome", "Troll", "BloodElf", "Draenei")
             for g in ("Male", "Female")]

# Where the models live now, and where they go so our override can sit on top.
DEMOTE = {"patch-y.mpq": "patch-o.mpq", "patch-z.mpq": "patch-p.mpq"}
OVERRIDE = "patch-z.mpq"


def find_model(path):
    """Read a model from the highest-priority archive that has it."""
    order = "23456789abcdefghijklmnopqrstuvwxyz"
    best = None
    for f in os.listdir(DATA):
        low = f.lower()
        if not (low.startswith("patch-") and low.endswith(".mpq")):
            continue
        suffix = low[6:-4]
        if len(suffix) != 1 or suffix not in order:
            continue
        blob = MPQ(os.path.join(DATA, f)).read_file(path)
        if blob and (best is None or order.index(suffix) > best[0]):
            best = (order.index(suffix), f, blob)
    return best


def retype_skin_extra(blob):
    """Flip every SKIN_EXTRA texture declaration to SKIN. Returns (data, count)."""
    data = bytearray(blob)
    count, offset = struct.unpack_from("<II", data, 0x50)
    changed = 0
    for i in range(count):
        entry = offset + i * 16
        if struct.unpack_from("<I", data, entry)[0] == TEX_SKIN_EXTRA:
            struct.pack_into("<I", data, entry, TEX_SKIN)
            changed += 1
    return bytes(data), changed


def deploy():
    for old, new in DEMOTE.items():
        src, dst = os.path.join(DATA, old), os.path.join(DATA, new)
        if os.path.exists(src) and not os.path.exists(dst):
            os.rename(src, dst)
            print(f"  demoted {old} -> {new}")
    shutil.copy(os.path.join(OUT, OVERRIDE), os.path.join(DATA, OVERRIDE))
    wdb = os.path.join(CLIENT, "Cache/WDB/enUS")
    for f in os.listdir(wdb) if os.path.isdir(wdb) else []:
        if f.endswith(".wdb"):
            os.remove(os.path.join(wdb, f))
    print(f"  installed data/{OVERRIDE}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="all 20 base-race models")
    ap.add_argument("--install", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)

    if args.install and os.popen("pgrep -if 'wow\\.exe'").read().strip():
        raise SystemExit("The WoW client is running - close it first.")

    files = []
    for race, gender in (ALL_RACES if args.all else RACES):
        path = f"Character\\{race}\\{gender}\\{race}{gender}.m2"
        found = find_model(path)
        if not found:
            print(f"  {race}{gender:8} not found, skipped")
            continue
        _, archive, blob = found
        patched, changed = retype_skin_extra(blob)
        if not changed:
            print(f"  {race}{gender:8} no SKIN_EXTRA texture, skipped")
            continue
        files.append((path, patched))
        print(f"  {race+gender:20} from {archive:14} {changed} texture(s) 8 -> 1")

    if not files:
        raise SystemExit("nothing to patch")

    size, _ = build(os.path.join(OUT, OVERRIDE), files)
    print(f"{OVERRIDE}  {size/1024:.0f} KB  ({len(files)} models)")

    m = MPQ(os.path.join(OUT, OVERRIDE))
    for path, blob in files:
        back = m.read_file(path)
        if back != blob:
            raise SystemExit(f"round-trip failed for {path}")
        types = [struct.unpack_from("<I", back, struct.unpack_from("<II", back, 0x50)[1] + i*16)[0]
                 for i in range(struct.unpack_from("<II", back, 0x50)[0])]
        assert TEX_SKIN_EXTRA not in types, path
    print("Round-trip verified, no SKIN_EXTRA left in any patched model.")

    if args.install:
        deploy()
        print("Restart the client.")
    else:
        print(f"Wrote {OUT}. Re-run with --install to deploy.")


if __name__ == "__main__":
    main()
