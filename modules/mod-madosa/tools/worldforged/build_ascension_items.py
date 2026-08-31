#!/usr/bin/env python3
"""Turn Ascension's real Worldforged items into item_template rows.

    python3 build_ascension_items.py            # print the SQL
    python3 build_ascension_items.py --write    # write it into data/sql/db-world/base/

Where the data comes from
-------------------------
Not from a website - both Ascension item databases are gone (db.ascension.gg no
longer resolves, db.exil.es does not answer, and the Wayback captures are empty
SPA shells). It comes from the Ascension *client's own cache*: every item the
client has ever been shown is written to

    Cache/WDB/enUS/<realm>/itemcache.wdb

as the raw SMSG_ITEM_QUERY_SINGLE_RESPONSE the server sent. Ascension left that
packet at the stock 3.3.5a layout, so it parses exactly - the parser checks that
every record is consumed to precisely its declared length, which a single wrong
field would break. That gives the genuine Ascension name, quality, item level,
required level, slot, armour, damage and stats for 2600+ Worldforged items.

Worldforged items identify themselves: Ascension tags every one of them with
"@Worldforged@" in the item description.

What cannot come across
-----------------------
The item *effects* do come across - see build_ascension_spells.py, which imports
the spells themselves into spell_dbc. This file only wires the items to them.

* **item_limit_category.** Ascension references categories from 1671 up; WotLK's
  ItemLimitCategory.dbc stops at 85, so those are cleared too.

Everything else transfers unchanged - including the original Ascension item ids,
which is safe because this world database's highest item entry is 90001 and
nothing lives in the 100000+ range Worldforged occupies.
"""

import argparse
import json
import struct
import sys
from pathlib import Path

HOME = Path.home()
WDB = (HOME / "Games/ascension-wow2/drive_c/Program Files/Ascension Launcher/resources"
              "/ascension-live/Cache/WDB/enUS/Rexxar - Conquest of Azeroth/itemcache.wdb")

WORLDFORGED_TAG = "@Worldforged@"
ITEM_CLASS_WEAPON = 2
ITEM_CLASS_ARMOR = 4
WDB_HEADER = 24
MAX_STATS = 10          # item_template has stat_type1..10
MAX_ITEM_LIMIT_CATEGORY = 85    # highest id in WotLK's ItemLimitCategory.dbc

# Ascension did not just add ItemDisplayInfo rows, it reused existing ones for
# other things: of the 1424 displays these items use, 918 exist in WotLK too and
# mean something completely different there. Display 15113 is a mage cape here
# and a flint axe on Ascension - leave it alone and the axe renders with the
# cape's texture, which is what a checkerboard model is.
#
# So every Worldforged display is re-numbered into a range nothing else uses, and
# the Ascension row is copied in under the new id. Nothing existing is disturbed
# and every item gets its true appearance. The client patch derives the same
# mapping from the same items, so both sides agree without sharing a file.
DISPLAY_ID_BASE = 200000     # this client's highest real display id is 69006


class Reader:
    def __init__(self, b):
        self.b, self.o = b, 0

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.o)[0]; self.o += 4; return v

    def i32(self):
        v = struct.unpack_from("<i", self.b, self.o)[0]; self.o += 4; return v

    def f32(self):
        v = struct.unpack_from("<f", self.b, self.o)[0]; self.o += 4; return v

    def cstr(self):
        end = self.b.index(b"\0", self.o)
        s = self.b[self.o:end].decode("utf-8", "replace"); self.o = end + 1; return s


def parse_item(entry, body):
    """SMSG_ITEM_QUERY_SINGLE_RESPONSE, stock 3.3.5a field order."""
    r = Reader(body)
    it = {"entry": entry}
    it["class"] = r.u32(); it["subclass"] = r.u32(); it["sound_override_subclass"] = r.i32()
    it["name"] = r.cstr(); r.cstr(); r.cstr(); r.cstr()
    it["displayid"] = r.u32(); it["quality"] = r.u32()
    it["flags"] = r.u32(); it["flags2"] = r.u32()
    it["buy_price"] = r.i32(); it["sell_price"] = r.u32()
    it["inventory_type"] = r.u32()
    it["allowable_class"] = r.i32(); it["allowable_race"] = r.i32()
    it["item_level"] = r.u32(); it["required_level"] = r.u32()
    it["required_skill"] = r.u32(); it["required_skill_rank"] = r.u32()
    it["required_spell"] = r.u32(); it["required_honor_rank"] = r.u32()
    it["required_city_rank"] = r.u32()
    it["required_rep_faction"] = r.u32(); it["required_rep_rank"] = r.u32()
    it["max_count"] = r.i32(); it["stackable"] = r.i32(); it["container_slots"] = r.u32()
    it["stats"] = [(r.u32(), r.i32()) for _ in range(r.u32())]
    it["scaling_stat_distribution"] = r.u32(); it["scaling_stat_value"] = r.u32()
    it["damage"] = [(r.f32(), r.f32(), r.u32()) for _ in range(2)]
    it["armor"] = r.u32(); it["resistances"] = [r.u32() for _ in range(6)]
    it["delay"] = r.u32(); it["ammo_type"] = r.u32(); it["ranged_mod_range"] = r.f32()
    it["spells"] = [(r.i32(), r.u32(), r.i32(), r.i32(), r.u32(), r.i32()) for _ in range(5)]
    it["bonding"] = r.u32(); it["description"] = r.cstr()
    it["page_text"] = r.u32(); it["language_id"] = r.u32(); it["page_material"] = r.u32()
    it["start_quest"] = r.u32(); it["lock_id"] = r.u32()
    it["material"] = r.i32(); it["sheath"] = r.u32()
    it["random_property"] = r.u32(); it["random_suffix"] = r.u32()
    it["block"] = r.u32(); it["item_set"] = r.u32(); it["max_durability"] = r.u32()
    it["area"] = r.u32(); it["map"] = r.i32()
    it["bag_family"] = r.u32(); it["totem_category"] = r.u32()
    it["sockets"] = [(r.u32(), r.u32()) for _ in range(3)]
    it["socket_bonus"] = r.u32(); it["gem_properties"] = r.u32()
    it["required_disenchant_skill"] = r.i32(); it["armor_damage_modifier"] = r.f32()
    it["duration"] = r.u32(); it["item_limit_category"] = r.u32(); it["holiday_id"] = r.u32()
    it["_consumed"], it["_size"] = r.o, len(body)
    return it


def selected_items(cache_path=None):
    """The Worldforged items this module imports, in id order.

    Shared with the client patch: both sides must select exactly the same items,
    or display_map() would number them differently and every item would point at
    the wrong picture.
    """
    everything = read_cache(cache_path or WDB)
    by_entry = {i["entry"]: i for i in everything}

    keep = {i["entry"] for i in everything if WORLDFORGED_TAG in (i["description"] or "")}
    untagged = 0
    for entry in sorted(located_items()):
        item = by_entry.get(entry)
        if entry in keep or not item:
            continue
        if item["class"] in (ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR):
            keep.add(entry)
            untagged += 1

    return sorted((by_entry[e] for e in keep), key=lambda i: i["entry"]), len(everything), untagged


def display_map(items):
    """Ascension display id -> the id it gets here. See DISPLAY_ID_BASE."""
    used = sorted({i["displayid"] for i in items if i["displayid"]})
    return {asc: DISPLAY_ID_BASE + n for n, asc in enumerate(used)}


def located_items():
    """Every item id that has a recorded Worldforged find location."""
    from build_ascension_spawns import load_discoveries, STARTER_DB, DISCOVERY_WORLDFORGED

    return {d["itemID"] for d in load_discoveries(STARTER_DB).values()
            if d.get("discoveryType") == DISCOVERY_WORLDFORGED}


def read_cache(path):
    data = path.read_bytes()
    out, off = [], WDB_HEADER
    while off + 8 <= len(data):
        entry, size = struct.unpack_from("<II", data, off)
        if entry == 0 and size == 0:
            break
        body = data[off + 8:off + 8 + size]
        off += 8 + size
        it = parse_item(entry, body)
        # The integrity check that makes this trustworthy: a misread field would
        # desynchronise the reader and this would not come out even.
        if it["_consumed"] != it["_size"]:
            raise SystemExit(f"item {entry}: read {it['_consumed']} of {it['_size']} bytes - layout mismatch")
        out.append(it)
    return out


def esc(s):
    return s.replace("\\", "\\\\").replace("'", "''")


COLUMNS = (
    "entry,class,subclass,SoundOverrideSubclass,name,displayid,Quality,Flags,FlagsExtra,"
    "BuyCount,BuyPrice,SellPrice,InventoryType,AllowableClass,AllowableRace,ItemLevel,RequiredLevel,"
    "RequiredSkill,RequiredSkillRank,requiredspell,requiredhonorrank,RequiredCityRank,"
    "RequiredReputationFaction,RequiredReputationRank,maxcount,stackable,ContainerSlots,"
    + ",".join(f"stat_type{i},stat_value{i}" for i in range(1, MAX_STATS + 1)) + ","
    "ScalingStatDistribution,ScalingStatValue,"
    "dmg_min1,dmg_max1,dmg_type1,dmg_min2,dmg_max2,dmg_type2,"
    "armor,holy_res,fire_res,nature_res,frost_res,shadow_res,arcane_res,"
    "delay,ammo_type,RangedModRange,"
    + ",".join(
        f"spellid_{i},spelltrigger_{i},spellcharges_{i},spellppmRate_{i},"
        f"spellcooldown_{i},spellcategory_{i},spellcategorycooldown_{i}"
        for i in range(1, 6)) + ","
    "bonding,description,PageText,LanguageID,PageMaterial,"
    "startquest,lockid,Material,sheath,RandomProperty,RandomSuffix,block,itemset,MaxDurability,"
    "area,Map,BagFamily,TotemCategory,"
    "socketColor_1,socketContent_1,socketColor_2,socketContent_2,socketColor_3,socketContent_3,"
    "socketBonus,GemProperties,RequiredDisenchantSkill,ArmorDamageModifier,duration,"
    "ItemLimitCategory,HolidayId"
)


def row(it, displays):
    stats = it["stats"][:MAX_STATS]
    stat_fields = []
    for i in range(MAX_STATS):
        stat_fields += list(stats[i]) if i < len(stats) else [0, 0]

    # The item query carries six values per spell slot; item_template has a
    # seventh, spellppmRate, which is server-side only and never sent - so it
    # stays 0 rather than being invented.
    spell_fields = []
    for spell_id, trigger, charges, cooldown, category, category_cooldown in it["spells"]:
        spell_fields += [spell_id, trigger, charges, 0, cooldown, category, category_cooldown]

    dmg = it["damage"]
    limit_category = it["item_limit_category"] if it["item_limit_category"] <= MAX_ITEM_LIMIT_CATEGORY else 0

    v = [
        it["entry"], it["class"], it["subclass"], it["sound_override_subclass"],
        f"'{esc(it['name'])}'", displays.get(it["displayid"], 0), it["quality"],
        it["flags"], it["flags2"],
        1, it["buy_price"], it["sell_price"], it["inventory_type"],
        it["allowable_class"], it["allowable_race"], it["item_level"], it["required_level"],
        it["required_skill"], it["required_skill_rank"],
        0,                                   # requiredspell - Ascension spell, dropped
        it["required_honor_rank"], it["required_city_rank"],
        it["required_rep_faction"], it["required_rep_rank"],
        it["max_count"], it["stackable"], it["container_slots"],
        *stat_fields,
        it["scaling_stat_distribution"], it["scaling_stat_value"],
        f"{dmg[0][0]:g}", f"{dmg[0][1]:g}", dmg[0][2],
        f"{dmg[1][0]:g}", f"{dmg[1][1]:g}", dmg[1][2],
        it["armor"], *it["resistances"],
        it["delay"], it["ammo_type"], f"{it['ranged_mod_range']:g}",
        *spell_fields,
        it["bonding"],
        "''",                                # description - drops the @Worldforged@ tag
        it["page_text"], it["language_id"], it["page_material"],
        0,                                   # startquest - Ascension quest, dropped
        it["lock_id"], it["material"], it["sheath"],
        it["random_property"], it["random_suffix"], it["block"], it["item_set"],
        it["max_durability"], it["area"], it["map"],
        it["bag_family"], it["totem_category"],
        *[x for pair in it["sockets"] for x in pair],
        it["socket_bonus"], it["gem_properties"], it["required_disenchant_skill"],
        f"{it['armor_damage_modifier']:g}", it["duration"], limit_category, it["holiday_id"],
    ]
    return "(" + ",".join(str(x) for x in v) + ")"


def build_sql(items, displays):
    head = (
        "-- Ascension's Worldforged items, as real item_template rows.\n"
        "--\n"
        "-- GENERATED by tools/worldforged/build_ascension_items.py - re-run the tool\n"
        "-- rather than editing this file.\n"
        "--\n"
        "-- Every value here is Ascension's own, read out of their client's item cache\n"
        "-- (see the tool's docstring for why that is the only surviving source and how\n"
        "-- the parse is verified). Names, qualities, item levels, slots, armour, damage\n"
        "-- and stats are exact; the original Ascension item ids are kept, which is safe\n"
        "-- because nothing in this database uses the 100000+ range.\n"
        "--\n"
        "-- Two things are deliberately cleared, because the data they point at does not\n"
        "-- exist in WotLK and a dangling reference is worse than an absent one:\n"
        "--   * requiredspell and startquest, which name Ascension spells and quests\n"
        "--   * ItemLimitCategory above 85, the highest WotLK ships\n"
        "--\n"
        f"-- {len(items)} items, using {len(displays)} re-numbered display ids from\n"
        f"-- {DISPLAY_ID_BASE} up - see the tool's DISPLAY_ID_BASE note for why the original\n"
        "-- ids cannot be used as they stand.\n"
        "--\n"
        "-- Most identify themselves by an '@Worldforged@' description tag. A few carry\n"
        "-- no tag but sit at a recorded Worldforged find, and the gear among those is\n"
        "-- taken too, so no location is left holding nothing.\n"
        "\n"
        "DELETE FROM `item_template` WHERE `entry` IN (SELECT `item` FROM `mod_madosa_worldforged_ascension_items`);\n"
        "DELETE FROM `mod_madosa_worldforged_ascension_items`;\n"
        "INSERT INTO `mod_madosa_worldforged_ascension_items` (`item`) VALUES\n"
        + ",\n".join(f"({i['entry']})" for i in items) + ";\n"
        "\n"
        f"INSERT INTO `item_template` ({COLUMNS}) VALUES\n"
    )
    return head + ",\n".join(row(i, displays) for i in items) + ";\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=Path, default=WDB, help="path to Ascension's itemcache.wdb")
    ap.add_argument("--write", action="store_true", help="write data/sql/db-world/base/worldforged_ascension_items.sql")
    args = ap.parse_args()

    if not args.cache.exists():
        raise SystemExit(f"item cache not found: {args.cache}")

    items, cached_total, untagged = selected_items(args.cache)
    if not items:
        raise SystemExit(f"no items tagged {WORLDFORGED_TAG} in {args.cache}")

    displays = display_map(items)
    sql = build_sql(items, displays)
    if args.write:
        out = Path(__file__).resolve().parents[2] / "data/sql/db-world/base/worldforged_ascension_items.sql"
        out.write_text(sql, encoding="utf-8")
        print(f"wrote {len(items)} items to {out}", file=sys.stderr)
    else:
        sys.stdout.write(sql)

    with_effects = sum(1 for i in items if any(s[0] > 0 for s in i["spells"]))
    print(f"{len(items)} Worldforged items of {cached_total} cached "
          f"({untagged} untagged but sitting at a recorded find); "
          f"{with_effects} carry an effect - run build_ascension_spells.py so those exist",
          file=sys.stderr)


if __name__ == "__main__":
    main()
