#!/usr/bin/env python3
"""Client patch for the Ascension Worldforged items' appearance.

    python3 build_client_patch.py              # build into ./out and report
    python3 build_client_patch.py --install    # ... and copy into the client

The item *data* (name, stats, slot) needs no client patch at all - in 3.3.5a the
client asks the server for item templates. Only the look is client-side, and it
comes from two places: an ItemDisplayInfo.dbc row, and the icon and model files
that row names.

Of the 1415 displays Ascension's Worldforged items use, 914 already exist in this
client. This patch supplies the other 501, plus the 192 icon files they name that
WotLK never shipped - Ascension imported them from later expansions
(inv_ring_mop11, inv_neck_ardenweald_01_red, ...) or drew their own.

3D models
---------
66 of the 501 rows name a model this client does not have, affecting 116 of 2615
items. Porting an M2 means its skins and textures too, for 4% of the items, so
instead those rows keep their correct Ascension *icon* and borrow the model of a
WotLK item of the same class, subclass and slot. Nothing renders broken and
nothing is invisible; those 116 items just hold a different-looking weapon than
they would on Ascension.

Archive letters
---------------
WoW loads patch archives in letter order and later ones win, so this writes
one file, `patch-enus-z.mpq` - a letter checked to be free in this client and
later than clientpatch's own `patch-enus-y`. The icons ride along in it rather
than in a second data/ archive: MPQ lookups are by path across the whole chain
and the base game already serves Interface\Icons out of locale-enUS.mpq. The DBC is built on
top of whatever the client reads today, so clientpatch's own ItemDisplayInfo rows
survive - but that also means **run this tool after clientpatch's
build_patches.py**, never before.
"""

import argparse
import os
import shutil
import struct
import sys
from pathlib import Path

HOME = Path.home()
CLIENT = HOME / "Games/world-of-warcraft-wrath-of-the-lich-king/drive_c/world_of_warcraft_wrath_of_the_lich_king"
LOCALE_DIR = CLIENT / "data/enus"
ASCENSION = HOME / "Games/ascension-wow2/drive_c/Program Files/Ascension Launcher/resources/ascension-live"
ASCENSION_DATA = ASCENSION / "Data"
ITEM_CACHE = ASCENSION / "Cache/WDB/enUS/Rexxar - Conquest of Azeroth/itemcache.wdb"

sys.path.insert(0, str(HOME / "azerothcore/modules/mod-madosa/tools/clientpatch"))
from dbc import DBC, DBCBuilder          # noqa: E402
from mpq import MPQ, build, hash_str     # noqa: E402

OUT = Path(__file__).resolve().parent / "out"

# Both letters were checked against this client rather than assumed free: patch-w
# and patch-x are already taken (patch-w by 27 MB of other content), and
# clientpatch owns patch-v and patch-enus-y. Later letters win, which is what puts
# these rows on top of everything else. Only this tool's *own* locale archive is
# skipped when looking for the DBC to build on, so clientpatch's patch-enus-y is
# picked up and its pet item rows survive.
MY_LOCALE_ARCHIVE = "patch-enus-z.mpq"
MY_DATA_ARCHIVE = "patch-y.mpq"

# ItemDisplayInfo.dbc field indices that hold string-block offsets.
STRING_FIELDS = [1, 2, 3, 4, 5, 6] + list(range(15, 23))
MODEL_FIELDS = [1, 2]
MODEL_TEXTURE_FIELDS = [3, 4]

# Where the client looks for an item's world model, by folder.
MODEL_FOLDERS = ["Weapon", "Shield", "Head", "Shoulder", "Cape", "Quiver", "Waist"]

WORLDFORGED_TAG = "@Worldforged@"
_LETTER_ORDER = "23456789abcdefghijklmnopqrstuvwxyz"


def _memoize_tables(archive):
    """Decrypt each MPQ's hash and block tables once instead of once per lookup.

    mpq.MPQ.read_file() re-reads and decrypts both tables on every call. That is
    fine for the handful of files clientpatch pulls, but here it means hundreds
    of lookups across dozens of multi-gigabyte archives, and pure-Python decrypt
    of an 8 MB table is not cheap. Caching them turns most of an hour into
    seconds, and touches nothing else about how the archive is read.
    """
    original = archive._table
    cache = {}

    def cached(off, n, key, esz):
        if key not in cache:
            cache[key] = original(off, n, key, esz)
        return cache[key]

    archive._table = cached


class ArchiveIndex:
    """Presence checks that do not re-decrypt the tables on every lookup."""

    def __init__(self, path):
        self.path = Path(path)
        self.name = self.path.name
        self.mpq = MPQ(str(path))
        _memoize_tables(self.mpq)

        table = self.mpq._table(self.mpq.htbl_off, self.mpq.htbl_n, "(hash table)", 16)
        self.keys = set()
        for i in range(self.mpq.htbl_n):
            h1, h2, _, block = struct.unpack_from("<IIIi", table, i * 16)
            if block >= 0:
                self.keys.add((h1, h2))

    def has(self, name):
        return (hash_str(name, 1), hash_str(name, 2)) in self.keys

    def read(self, name):
        return self.mpq.read_file(name)


def open_archives(*dirs):
    out = []
    for d in dirs:
        if not Path(d).is_dir():
            continue
        for n in sorted(os.listdir(d)):
            if n.lower().endswith(".mpq") and n != MY_LOCALE_ARCHIVE and n != MY_DATA_ARCHIVE:
                try:
                    out.append(ArchiveIndex(Path(d) / n))
                except Exception as e:
                    print(f"  (skipping {n}: {e})", file=sys.stderr)
    return out


def archive_priority(filename):
    """WoW's locale load order: locale, patch, then patch-2..9, a..z. Later wins."""
    low = filename.lower()
    if not low.endswith(".mpq") or low == MY_LOCALE_ARCHIVE:
        return None
    if low == "locale-enus.mpq":
        return -2
    if low == "patch-enus.mpq":
        return -1
    if low.startswith("patch-enus-") and len(low) == len("patch-enus-x.mpq"):
        return _LETTER_ORDER.find(low[len("patch-enus-")])
    return None


def current_client_dbc(name):
    """The DBC the client reads today, this tool's own archive aside."""
    candidates = []
    for filename in os.listdir(LOCALE_DIR):
        priority = archive_priority(filename)
        if priority is not None:
            candidates.append((priority, filename))
    for _, filename in sorted(candidates, reverse=True):
        blob = MPQ(str(LOCALE_DIR / filename)).read_file(f"DBFilesClient\\{name}")
        if blob:
            return blob, filename
    raise SystemExit(f"no enabled locale archive provides {name}")


# Spell.dbc string fields: the four 16-slot locale blocks (name, subtext,
# description, aura description). The mask that follows each block is an integer
# and must not be treated as an offset.
SPELL_STRING_FIELDS = (list(range(136, 152)) + list(range(153, 169))
                       + list(range(170, 186)) + list(range(187, 203)))
SPELLICON_STRING_FIELDS = [1]

# Item.dbc has no strings at all. Field order verified against this client's own
# rows: item 25 "Worn Shortsword" reads (25, 2, 7, -1, 1, 1542, 21, 3), matching
# its item_template row field for field.
ITEM_DBC_FIELDS = ("class", "subclass", "sound_override_subclass",
                   "material", "displayid", "inventory_type", "sheath")


def append_dbc_rows(blob, rows, string_fields, source):
    """Append rows to a DBC without parsing the ones already in it.

    Spell.dbc is ~49 MB and reading its 49840 records into Python lists costs
    hundreds of megabytes, so the existing records are left as the bytes they
    already are and the new ones are packed on the end - the same trick
    clientpatch uses on this file.

    `rows` are field lists taken from `source`; their string offsets point into
    *its* string block, so each one is re-read from there and re-added here.
    """
    _, rc, fc, rs, sb = struct.unpack_from("<4sIIII", blob, 0)
    records = bytearray(blob[20:20 + rc * rs])
    strings = bytearray(blob[20 + rc * rs:20 + rc * rs + sb])

    def addstr(text):
        if not text:
            return 0
        offset = len(strings)
        strings.extend(text.encode("latin1", "replace") + b"\x00")
        return offset

    for row in rows:
        out = list(row)
        for i in string_fields:
            out[i] = addstr(read_dbc_string(source, row[i]))
        records.extend(struct.pack(f"<{fc}I", *[v & 0xFFFFFFFF for v in out]))

    header = struct.pack("<4sIIII", b"WDBC", rc + len(rows), fc, rs, len(strings))
    return header + bytes(records) + bytes(strings), rc, rc + len(rows)


def read_dbc_string(dbc, offset):
    """dbc.s() with bounds checks - a few Ascension rows carry a stray offset."""
    if not offset or offset >= dbc.sb:
        return ""
    start = dbc.sblock + offset
    end = dbc.d.find(b"\0", start, dbc.sblock + dbc.sb)
    return "" if end < 0 else dbc.d[start:end].decode("latin1")


# --------------------------------------------------------------------------
# Which displays do the Worldforged items need?
# --------------------------------------------------------------------------

def worldforged_displays():
    """(ascension display id -> local id) plus what kind of item uses each.

    The mapping comes from build_ascension_items so the SQL and this patch number
    the displays identically - they must, or every item would point at the wrong
    picture.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from build_ascension_items import selected_items, display_map

    items, _, _ = selected_items()
    mapping = display_map(items)
    kinds = {}
    for it in items:
        kinds.setdefault(it["displayid"], (it["class"], it["subclass"], it["inventory_type"]))
    return mapping, kinds, items


def wotlk_display_donors():
    """One existing display per (class, subclass, slot), to borrow a model from.

    Only used for the rows whose Ascension model this client does not have; the
    item still shows its own Ascension icon, it just holds a WotLK-shaped weapon.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from build_ascension_spells import query

    rows = query("SELECT class, subclass, InventoryType, MIN(displayid) FROM item_template "
                 "WHERE entry < 100000 AND displayid > 0 GROUP BY class, subclass, InventoryType;")
    return {(int(c), int(sc), int(inv)): int(d) for c, sc, inv, d in rows}


def find_model_folder(archives, model):
    base = model.rsplit(".", 1)[0]
    for folder in MODEL_FOLDERS:
        for ext in (".m2", ".mdx"):
            if any(a.has(f"Item\\ObjectComponents\\{folder}\\{base}{ext}") for a in archives):
                return folder
    return None


def pick_donor_display(wotlk, by_kind, kind):
    """A WotLK display for the same class/subclass/slot, to borrow a model from."""
    for candidate in by_kind.get(kind, ()):
        row = wotlk.get(candidate)
        if row and wotlk_str(row, 1):
            return row
    return None


def wotlk_str(pair, field):
    dbc, row = pair
    return dbc.s(row[field])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--install", action="store_true", help="copy the built archives into the client")
    args = ap.parse_args()

    OUT.mkdir(exist_ok=True)

    print("opening client archives ...")
    client_archives = open_archives(CLIENT / "data", LOCALE_DIR)
    print(f"  {len(client_archives)} archives")

    print("opening Ascension archives ...")
    ascension_archives = open_archives(ASCENSION_DATA, ASCENSION_DATA / "enUS")
    print(f"  {len(ascension_archives)} archives")

    # Ascension's ItemDisplayInfo lives in patch-M, not in a locale archive.
    asc_blob = None
    for a in ascension_archives:
        blob = a.read("DBFilesClient\\ItemDisplayInfo.dbc")
        if blob and (asc_blob is None or len(blob) > len(asc_blob)):
            asc_blob = blob
    if not asc_blob:
        raise SystemExit("Ascension ships no ItemDisplayInfo.dbc we can read")
    asc_path = OUT / "ascension_ItemDisplayInfo.dbc"
    asc_path.write_bytes(asc_blob)
    asc = DBC(str(asc_path))

    base_blob, base_from = current_client_dbc("ItemDisplayInfo.dbc")
    base_path = OUT / "base_ItemDisplayInfo.dbc"
    base_path.write_bytes(base_blob)
    base = DBC(str(base_path))
    print(f"Ascension ItemDisplayInfo: {asc.rc} rows | client's ({base_from}): {base.rc} rows")

    mapping, kinds, wf_items = worldforged_displays()
    asc_rows = {r[0]: r for r in asc.rows()}
    base_rows = {r[0]: r for r in base.rows()}
    donors = wotlk_display_donors()
    print(f"Worldforged displays: {len(mapping)} re-numbered from {min(mapping.values())} up")

    builder = DBCBuilder(str(base_path))
    icons_needed = set()
    substituted = missing_rows = 0

    for asc_id, local_id in sorted(mapping.items(), key=lambda kv: kv[1]):
        src = asc_rows.get(asc_id)
        if not src:
            # Not in Ascension's table either. Fall back to whatever this client
            # has under that id - wrong more often than not, but better than an
            # item pointing at a display that exists nowhere.
            src = base_rows.get(asc_id)
            if not src:
                missing_rows += 1
                continue
            strings = {f: base.s(src[f]) for f in STRING_FIELDS}
        else:
            strings = {f: asc.s(src[f]) for f in STRING_FIELDS}

        row = list(src)
        row[0] = local_id

        if any(strings[f] and not find_model_folder(client_archives, strings[f]) for f in MODEL_FIELDS):
            donor = base_rows.get(donors.get(kinds.get(asc_id, ()), 0))
            if donor:
                for f in MODEL_FIELDS + MODEL_TEXTURE_FIELDS + list(range(15, 23)):
                    strings[f] = base.s(donor[f])
            else:
                for f in MODEL_FIELDS + MODEL_TEXTURE_FIELDS:
                    strings[f] = ""
            substituted += 1

        for f in (5, 6):
            if strings[f]:
                icons_needed.add(strings[f])

        for f in STRING_FIELDS:
            row[f] = builder.addstr(strings[f])
        builder.append(row)

    if missing_rows:
        print(f"  WARNING: {missing_rows} display(s) found in neither table")
    print(f"  {substituted} rows had a model this client lacks and borrowed a WotLK one")

    dbc_out = OUT / "client_ItemDisplayInfo.dbc"
    total = builder.save(str(dbc_out))
    print(f"ItemDisplayInfo.dbc: {base.rc} -> {total} rows")

    # ---- Item.dbc: what makes the inventory icon resolve -------------------
    # The model comes from the displayid the server sends with the item, but the
    # *icon* is looked up through Item.dbc, and an item the client has no row for
    # falls back to the question mark however good its ItemDisplayInfo row is.
    # That is the whole reason a Worldforged item could show its true model and a
    # "?" at the same time.
    item_blob, item_from = current_client_dbc("Item.dbc")
    item_path = OUT / "base_Item.dbc"
    item_path.write_bytes(item_blob)
    base_items = DBC(str(item_path))
    known_items = {r[0] for r in base_items.rows()}

    new_items = []
    for it in wf_items:
        if it["entry"] in known_items:
            continue
        row = [it["entry"]]
        for field in ITEM_DBC_FIELDS:
            row.append(mapping.get(it["displayid"], 0) if field == "displayid" else it[field])
        new_items.append(row)

    patched_items, items_before, items_after = append_dbc_rows(
        item_blob, new_items, [], base_items)
    print(f"Item.dbc (from {item_from}): {items_before} -> {items_after} rows")

    # ---- the spells behind the item effects -------------------------------
    # The server already knows these (they are imported into spell_dbc); the
    # client needs its own rows or the tooltip has nothing to print. Both sides
    # take the same selection, clamped the same way, from select_spells().
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from build_ascension_spells import select_spells

    print("selecting spells ...")
    spells, asc_spell_dbc = select_spells(quiet=True)

    spell_blob, spell_from = current_client_dbc("Spell.dbc")
    patched_spells, before, after = append_dbc_rows(
        spell_blob, list(spells.values()), SPELL_STRING_FIELDS, asc_spell_dbc)
    print(f"Spell.dbc (from {spell_from}): {before} -> {after} rows")

    # Their icons. Ascension's SpellIcon rows name .blp files, most of which this
    # client already has; only the genuinely absent ones are carried over.
    icon_blob, icon_from = current_client_dbc("SpellIcon.dbc")
    icon_path = OUT / "base_SpellIcon.dbc"
    icon_path.write_bytes(icon_blob)
    client_icons = {r[0] for r in DBC(str(icon_path)).rows()}

    asc_icon_path = OUT / "ascension_SpellIcon.dbc"
    if not asc_icon_path.exists():
        for a in ascension_archives:
            blob = a.read("DBFilesClient\\SpellIcon.dbc")
            if blob:
                asc_icon_path.write_bytes(blob)
                break
    asc_icons = DBC(str(asc_icon_path))
    asc_icon_rows = {r[0]: r for r in asc_icons.rows()}

    wanted_icons = {row[i] for row in spells.values() for i in (133, 134) if row[i]}
    new_icons = [asc_icon_rows[i] for i in sorted(wanted_icons - client_icons) if i in asc_icon_rows]
    patched_icons, icons_before, icons_after = append_dbc_rows(
        icon_blob, new_icons, SPELLICON_STRING_FIELDS, asc_icons)
    print(f"SpellIcon.dbc (from {icon_from}): {icons_before} -> {icons_after} rows")

    for row in new_icons:
        path = read_dbc_string(asc_icons, row[1])
        if path:
            icons_needed.add(path.split("\\")[-1])

    missing_icons = sorted(i for i in icons_needed
                           if not any(a.has(f"Interface\\Icons\\{i}.blp") for a in client_archives))
    print(f"total icons referenced: {len(icons_needed)}, still missing: {len(missing_icons)}")

    files = []
    not_found = []
    for icon in missing_icons:
        name = f"Interface\\Icons\\{icon}.blp"
        blob = None
        for a in ascension_archives:
            if a.has(name):
                blob = a.read(name)
                if blob:
                    break
        if blob:
            files.append((name, blob))
        else:
            not_found.append(icon)
    if not_found:
        print(f"  WARNING: {len(not_found)} icons not readable from Ascension either: {not_found[:8]}")

    # Everything in one archive, icons included. MPQ lookups are by path across
    # the whole chain and locale archives take part in it - the base game already
    # serves Interface\Icons from locale-enUS.mpq - so a locale archive can carry
    # them just as well, and that leaves a single file to hand anyone.
    dbcs = [("DBFilesClient\\ItemDisplayInfo.dbc", dbc_out.read_bytes()),
            ("DBFilesClient\\Item.dbc", patched_items),
            ("DBFilesClient\\Spell.dbc", patched_spells),
            ("DBFilesClient\\SpellIcon.dbc", patched_icons)]
    size, _ = build(str(OUT / MY_LOCALE_ARCHIVE), dbcs + files)
    print(f"{MY_LOCALE_ARCHIVE}  {size / 1024 / 1024:6.2f} MB  "
          f"({len(dbcs)} DBCs + {len(files)} icons)")

    if args.install:
        shutil.copy(OUT / MY_LOCALE_ARCHIVE, LOCALE_DIR / MY_LOCALE_ARCHIVE)
        # An earlier layout split the icons into their own data/ archive; drop it
        # so a client updated from that version does not keep a stale copy.
        stale = CLIENT / "data" / MY_DATA_ARCHIVE
        if stale.exists():
            stale.unlink()
            print(f"removed the now-unused {MY_DATA_ARCHIVE}")
        print(f"installed into {CLIENT}")
    else:
        print(f"not installed - re-run with --install (output in {OUT})")


if __name__ == "__main__":
    main()
