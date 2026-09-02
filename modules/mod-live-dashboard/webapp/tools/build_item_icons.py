#!/usr/bin/env python3
"""Pulls every item icon out of the client for the dashboard's character sheet.

An item's icon is not in the item at all: item_template.displayid points at an
ItemDisplayInfo.dbc row, whose field 5 names a texture under Interface\\Icons.
This reads that DBC out of the locale archives, then the BLP behind every
distinct name - the icons live in the locale archives too, with custom ones in
the data patches - and writes them as 64 px webp files to
webapp/icons/<name>.webp plus icons/index.json mapping display id -> name.
server.py serves the files under /icons/ and uses the index to put the icon
name into /api/character.

Archives are searched in the client's own priority order, later patches first,
so a display row or icon added by a custom patch (mod-madosa's Ascension items
live in patch-enus-y and patch-v) wins over the stock one exactly as it does
in the game.

Usage: build_item_icons.py <client dir> [--out <dir>]
"""

import argparse
import io
import json
import re
import sys
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "mod-madosa" / "tools" / "clientpatch"))
from dbc import DBC  # noqa: E402
from mpq import MPQ  # noqa: E402

ICON_FIELD = 5   # ItemDisplayInfo.dbc: InventoryIcon[0]

# Spell.dbc (3.3.5, 234 fields): Description_enUS, EffectDieSides[3], EffectBasePoints[3].
# An effect's shown value is base points plus die sides - the client rolls the die at
# its maximum for a tooltip, and for the flat "+N rating" spells the die is 1.
SPELL_DESC_FIELD = 170
SPELL_DIESIDES_FIELD = 74
SPELL_BASEPOINTS_FIELD = 80
ICON_SIZE = 64


def priority(name: str) -> tuple:
    """WoW loads base archives first and patches after, letters after digits,
    and the last one loaded wins. Higher tuple = loaded later = wins."""
    n = name.lower()
    if not n.endswith(".mpq"):
        return None
    m = re.match(r"patch(?:-enus)?(?:-([0-9a-z]))?\.mpq$", n)
    if m:
        suffix = m.group(1)
        if suffix is None:
            return (2, 0, "")
        if suffix.isdigit():
            return (2, 1, suffix)
        return (2, 2, suffix)
    return (1, 0, n)   # base archives, in name order


def ordered_archives(*directories: Path):
    """Newest-wins order across every directory given: every readable archive,
    highest priority first, a locale archive ahead of the data archive of the
    same patch level (the game loads it after)."""
    found = []
    for rank, directory in enumerate(directories):
        for path in directory.iterdir():
            p = priority(path.name)
            if p is not None and path.is_file():
                found.append((p + (rank,), path))
    found.sort(reverse=True)
    return [(path.name, MPQ(str(path))) for _, path in found]


def read_any(archives, path: str):
    for _, archive in archives:
        try:
            data = archive.read_file(path)
        except Exception:
            continue
        if data:
            return data
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("client", type=Path)
    parser.add_argument("--out", type=Path, default=HERE.parent / "icons")
    args = parser.parse_args()

    data_dir = args.client / "data"
    if not data_dir.is_dir():
        data_dir = args.client / "Data"
    locale_dirs = [d for d in data_dir.iterdir() if d.is_dir() and len(d.name) == 4]
    if not locale_dirs:
        raise SystemExit(f"no locale directory (enus, dede, ...) under {data_dir}")

    # One search order for everything: locale patches and data patches
    # interleaved the way the client loads them.
    archives = ordered_archives(data_dir, locale_dirs[0])

    raw = read_any(archives, "DBFilesClient\\ItemDisplayInfo.dbc")
    if not raw:
        raise SystemExit("ItemDisplayInfo.dbc not found")
    tmp = args.out / ".ItemDisplayInfo.dbc"
    args.out.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(raw)
    dbc = DBC(str(tmp))
    tmp.unlink()

    index = {}
    names = set()
    for row in dbc.rows():
        icon = dbc.s(row[ICON_FIELD])
        if not icon:
            continue
        index[row[0]] = icon.lower()
        names.add(icon)
    print(f"{len(index)} display rows, {len(names)} distinct icons")

    started = time.time()
    written = missing = 0
    for i, name in enumerate(sorted(names)):
        target = args.out / (name.lower() + ".webp")
        if target.exists():
            continue
        blob = read_any(archives, "Interface\\Icons\\" + name + ".blp")
        if not blob:
            missing += 1
            continue
        try:
            img = Image.open(io.BytesIO(blob)).convert("RGBA")
        except Exception:
            missing += 1
            continue
        if img.size != (ICON_SIZE, ICON_SIZE):
            img = img.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
        img.save(target, "WEBP", quality=80, method=4)
        written += 1
        if i % 1000 == 0:
            print(f"  {i}/{len(names)} ({time.time() - started:.0f}s)")

    (args.out / "index.json").write_text(json.dumps(index, separators=(",", ":")))

    # The "Equip:" lines of a tooltip are spell descriptions, with $s1..$s3
    # standing for the spell's effect values. Spell.dbc is the only source, so
    # every spell that has a description goes into spells.json as
    # [description, s1, s2, s3]; server.py substitutes the values.
    raw = read_any(archives, "DBFilesClient\\Spell.dbc")
    if raw:
        tmp.write_bytes(raw)
        spells = DBC(str(tmp))
        tmp.unlink()
        text = {}
        for row in spells.rows():
            desc = spells.s(row[SPELL_DESC_FIELD])
            if not desc:
                continue
            values = []
            for k in range(3):
                bp = row[SPELL_BASEPOINTS_FIELD + k]
                bp = bp - 0x100000000 if bp >= 0x80000000 else bp
                values.append(bp + row[SPELL_DIESIDES_FIELD + k])
            text[row[0]] = [desc, *values]
        (args.out / "spells.json").write_text(json.dumps(text, separators=(",", ":"), ensure_ascii=False))
        print(f"{len(text)} spell descriptions")

    # What a worn item's enchantments and random suffix mean. Most of the gear
    # on this realm carries its stats this way - playerbots roll random
    # suffixes and enchants onto everything - and none of it is in
    # item_template: the enchant ids are in item_instance, their names in
    # SpellItemEnchantment.dbc ("+$i Stamina"), the suffix's name and
    # allocation in ItemRandomSuffix.dbc, and the points $i scales from in
    # RandPropPoints.dbc, by item level. All four go into itemdata.json.
    def load(name):
        raw = read_any(archives, f"DBFilesClient\\{name}.dbc")
        if not raw:
            return None
        tmp.write_bytes(raw)
        parsed = DBC(str(tmp))
        tmp.unlink()
        return parsed

    ench = load("SpellItemEnchantment")
    suffix = load("ItemRandomSuffix")
    props = load("ItemRandomProperties")
    points = load("RandPropPoints")
    if ench and suffix and props and points:
        data = {
            "enchants": {row[0]: [ench.s(row[14]), list(row[2:5])] for row in ench.rows() if ench.s(row[14])},
            "suffixes": {row[0]: [suffix.s(row[1]), list(row[19:24]), list(row[24:29])] for row in suffix.rows()},
            "properties": {row[0]: [props.s(row[7]), list(row[2:7])] for row in props.rows()},
            "points": {row[0]: [list(row[1:6]), list(row[6:11]), list(row[11:16])] for row in points.rows()},
        }
        (args.out / "itemdata.json").write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
        print(f"{len(data['enchants'])} enchantments, {len(data['suffixes'])} suffixes, "
              f"{len(data['properties'])} random properties")
    total = sum(f.stat().st_size for f in args.out.glob("*.webp"))
    print(f"done: {written} written, {missing} missing, {total / 1e6:.0f} MB in {args.out}")


if __name__ == "__main__":
    main()
