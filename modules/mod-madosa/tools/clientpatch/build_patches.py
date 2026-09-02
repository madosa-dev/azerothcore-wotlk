#!/usr/bin/env python3
"""Rebuild the client patches for the mod-madosa companion pets.

Everything a pet looks like is described in PETS below. Change a value, run this
script, restart the client (and the worldserver if you touched a scale), done.

    python3 build_patches.py            # build into ./out and print the SQL
    python3 build_patches.py --install  # ... and copy into the client + server

What it produces:
    out/patch-v.mpq           models, textures and icons        -> <client>/data/
    out/patch-enus-y.mpq      the five patched DBCs             -> <client>/data/enus/
    out/pet_ascension_models.sql                                -> apply to acore_world
    out/CreatureModelData.dbc, CreatureDisplayInfo.dbc,
    out/ItemDisplayInfo.dbc                                     -> <server>/data/dbc/
    out/client_*.dbc          the client variants, already inside patch-enus-y.mpq

Why two archives: models and icons are locale-neutral and live in data/, while
DBCs are only ever read from the locale directory data/enus/. A DBC placed in
data/ is silently ignored because locale-enus.mpq outranks it.

Why client_* and plain names differ: the client's DBCs are not the server's. The
HD model pack (patch-enus-f.mpq) ships 206 extra CreatureModelData rows and its
own CreatureDisplayInfo texture paths, so the client variant is built on top of
whatever the client actually reads, found at build time by client_dbc(). The
server variant stays on the server's own extracted copies. Both get identical
appended rows.
"""

import argparse
import json
import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mpq import MPQ, build
from dbc import DBC, DBCBuilder, I

# --------------------------------------------------------------------------
# Paths - adjust if you move things around.
# --------------------------------------------------------------------------
HOME = os.path.expanduser("~")
CLIENT = os.path.join(HOME, "Games/world-of-warcraft-wrath-of-the-lich-king"
                            "/drive_c/world_of_warcraft_wrath_of_the_lich_king")
ASCENSION = os.path.join(HOME, "Games/ascension-wow2/drive_c/Program Files"
                               "/Ascension Launcher/resources/ascension-live/Data")
SERVER_DBC = os.path.join(HOME, "azerothcore/env/dist/data/dbc")
LOCALE_DIR = os.path.join(CLIENT, "data/enus")

# Our own output, excluded when looking for the file we are about to replace.
OUR_ARCHIVES = {"patch-enus-y.mpq", "patch-enus-z.mpq"}

# WoW loads locale archives in this order and later ones win: locale-enUS.MPQ,
# patch-enUS.MPQ, then patch-enUS-2 .. -9, then -A .. -Z. A ".disabled"
# suffix drops out on its own because the name no longer ends in .mpq.
_LETTER_ORDER = "23456789abcdefghijklmnopqrstuvwxyz"


def _archive_priority(filename):
    name = filename.lower()
    if name in OUR_ARCHIVES:
        return None
    if name == "locale-enus.mpq":
        return -2
    if name == "patch-enus.mpq":
        return -1
    if name.startswith("patch-enus-") and name.endswith(".mpq"):
        suffix = name[len("patch-enus-"):-4]
        if len(suffix) == 1 and suffix in _LETTER_ORDER:
            return _LETTER_ORDER.index(suffix)
    return None


def client_dbc(name):
    """The DBC the client actually reads today, ignoring our own patches.

    Hardcoding a source archive here was a real bug: the HD model pack ships its
    own CreatureModelData.dbc (1537 rows against vanilla's 1331) and rewrites
    CreatureDisplayInfo texture paths. Building on the *server's* copy silently
    dropped all of that and made HD creatures render as green blobs.
    """
    candidates = []
    for filename in os.listdir(LOCALE_DIR):
        priority = _archive_priority(filename)
        if priority is not None:
            candidates.append((priority, filename))
    for _, filename in sorted(candidates, reverse=True):
        blob = MPQ(os.path.join(LOCALE_DIR, filename)).read_file("DBFilesClient\\" + name)
        if blob:
            return blob, filename
    raise SystemExit(f"no enabled locale archive provides {name}")

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# --------------------------------------------------------------------------
# The pets. This is the only part you normally edit.
# --------------------------------------------------------------------------
# icon          file name (no path, no .blp) under Interface\Icons\
# model         path inside the Ascension archive
# archive       which Ascension MPQ holds that model's folder
# texture       CreatureDisplayInfo texture variation, "" if the model has its
#               textures baked in. Ascension models usually carry a "type 11"
#               texture, which means the skin comes from here, not from the .m2.
# dbc_scale     scale stored in CreatureDisplayInfo
# display_scale scale stored in creature_template_model (server side, tunable
#               with a single UPDATE without rebuilding anything)
#
# Render height is roughly the model's vertex bounding box (M2 offset 0xA0)
# times dbc_scale times display_scale. Aim for ~1.0; a player is ~2.0.

PETS = {
    "Lootbot": dict(
        creature=16549, item=23015, spell=28740,
        archive="patch-CM.MPQ", model=r"Creature\mechagonpet\mechagonpet.m2",
        texture="mechagonpet_junker", dbc_scale=1.0, display_scale=0.14,
        icon="custom_Engineering_60_robot", icon_archive="patch-I.MPQ",
        spell_name="Lootbot",
        spell_desc="Right Click to summon and dismiss your Lootbot. While summoned, "
                   "it automatically loots anything you could loot yourself.",
        modeldata_id=7501, display_id=33001, itemdisplay_id=69001, spellicon_id=4401,
        model_info=(1, 1, 2),      # BoundingRadius, CombatReach, Gender
    ),
    "Craftbot": dict(
        creature=28883, item=39286, spell=52615,
        archive="patch-CH.MPQ", model=r"Creature\harvestgolempet\harvestgolempet.m2",
        texture="harvestgolempet_4206562", dbc_scale=0.25, display_scale=1.0,
        icon="inv_engineering_90_toolbox_orange", icon_archive="patch-I.MPQ",
        spell_name="Craftbot",
        spell_desc="Right Click to summon and dismiss your Craftbot. While summoned, "
                   "it offers training in every profession - anywhere, anytime.",
        modeldata_id=7502, display_id=33002, itemdisplay_id=69002, spellicon_id=4402,
        model_info=(0, 0, 0),
    ),
    "Questbot": dict(
        creature=24388, item=33816, spell=43697,
        archive="patch-CC.MPQ", model=r"Creature\clockworkbeagle\clockworkbeagle.m2",
        texture="clockworkbeagle_gold", dbc_scale=1.0, display_scale=1.0,
        icon="70_professions_scroll_02", icon_archive="patch-I.MPQ",
        spell_name="Questbot",
        spell_desc="Right Click to summon and dismiss your Questbot. While summoned, "
                   "it offers every quest for the instance you are in, and takes back "
                   "finished instance quests from anywhere.",
        modeldata_id=7503, display_id=33003, itemdisplay_id=69003, spellicon_id=4403,
        model_info=(0, 0, 2),
    ),
    "Bankbot": dict(
        creature=25146, item=34518, spell=45174,
        archive="patch-CM.MPQ", model=r"Creature\mechanicalhandpet\mechanicalhandpet.m2",
        texture="mechanicalhandpetcopper", dbc_scale=0.5, display_scale=0.45,
        icon="achievement_guildperk_mobilebanking", icon_archive="patch-I.MPQ",
        spell_name="Bankbot",
        spell_desc="Right Click to summon and dismiss your Bankbot. While summoned, "
                   "it gives you access to your bank - anywhere, anytime.",
        modeldata_id=7504, display_id=33004, itemdisplay_id=69004, spellicon_id=4404,
        model_info=(0, 0, 2),
    ),
    "Auctionbot": dict(
        creature=25147, item=34519, spell=45175,
        archive="patch-CM.MPQ", model=r"Creature\mechanicalparrotpet\mechanicalparrotpet.m2",
        texture="mechanicalparrotpet", dbc_scale=1.0, display_scale=0.13,
        icon="ACHIEVEMENT_GUILDPERK_CASHFLOW", icon_archive="patch-I.MPQ",
        spell_name="Auctionbot",
        spell_desc="Right Click to summon and dismiss your Auctionbot. While summoned, "
                   "it gives you access to the auction house - anywhere, anytime.",
        modeldata_id=7505, display_id=33005, itemdisplay_id=69005, spellicon_id=4405,
        model_info=(0, 0, 2),
    ),
    "Classtrainer": dict(
        creature=24480, item=33993, spell=43918,
        archive="patch-CG.MPQ", model=r"Creature\Gizmo\Gizmo.m2",
        texture="", dbc_scale=1.0, display_scale=1.0,
        icon="inv_custom_trainerBook", icon_archive="patch-I.MPQ",
        spell_name="Classtrainer",
        spell_desc="Right Click to summon and dismiss your Classtrainer. While summoned, "
                   "it offers class training for your class - anywhere, anytime.",
        modeldata_id=7506, display_id=33006, itemdisplay_id=69006, spellicon_id=4406,
        model_info=(0, 0, 2),
    ),
}

# Spells that are not a pet summon but still want a proper name and tooltip.
# Icons stay untouched here - the Scroll of Professions uses a plain Blizzard
# scroll display, so only the text needs rewriting.
EXTRA_SPELLS = {
    36177: dict(   # inert "Dummy" spell, referenced by nothing else; carries the
                   # Scroll of Professions so the client considers the item usable
        name="Scroll of Professions",
        desc="Grants one additional primary profession slot, letting you learn "
             "beyond the usual two. The scroll is consumed.",
    ),
    62514: dict(   # was "Alarming Clockbot", repurposed as Repairbot
        name="Repairbot",
        desc="Right Click to summon and dismiss your Repairbot. While summoned, "
             "it repairs your equipment anywhere, for the usual cost.",
    ),
    30156: dict(   # was "Hippogryph Hatchling", repurposed as Mailbot
        name="Mailbot",
        desc="Right Click to summon and dismiss your Mailbot. While summoned, "
             "it gives you access to your mailbox - anywhere, anytime.",
    ),
    75906: dict(   # was "Lil' XT", repurposed as Omnibot
        name="Omnibot",
        desc="Right Click to summon and dismiss your Omnibot. While summoned, it "
             "offers your bank, the auction house, your mailbox, repairs and "
             "training - and loots your kills.",
    ),
}

# Wholly new spells: unlike EXTRA_SPELLS/PETS these ids do not exist yet, so a
# fresh row is appended to Spell.dbc (both the client and the server copy - the
# server must recognise the id too, or CastSpell(id) just fails there). Each is
# a purely visual, permanent, self-only dummy aura: CastingTimeIndex 1 (instant),
# RangeIndex 1 ("Self Only"), DurationIndex 21 (Duration[0] = -1, i.e. until
# removed) - all verified against this client's own SpellCastTimes/SpellRange/
# SpellDuration.dbc. Ids start at 900001, comfortably above the ~80864 real max.
# `icon`/`icon_archive` are optional: an entry that names them gets a brand new
# SpellIcon.dbc row and its .blp copied out of an Ascension archive, while one
# that only gives `spellicon_id` points at an icon this client already ships.
# `attributes`/`attributes_ex3` are optional too, and default to 0.
NEW_SPELLS = {
    "XP Boost": dict(
        spell_id=900001, spellicon_id=4501,
        icon="xpbonus_icon", icon_archive="patch-I.MPQ",
        name="XP Boost",
        desc="You are receiving bonus experience.",
    ),
    # The three Hardcore PvP marks (mod_madosa_hardcore_pvp.cpp). These auras
    # are load-bearing rather than decorative - a chest only drops between two
    # Hardcore players, so the mark is how a killer knows a target is carrying
    # anything - which is why they carry NO_AURA_CANCEL (0x80000000): a player
    # must not be able to right-click their status off. Plus ALLOW_AURA_WHILE_DEAD
    # (attributes_ex3 0x00100000) so the mark survives the corpse run, and the
    # while-dead/mounted/sitting bits so nothing ever refuses the cast.
    # Icons are this client's own: Spell_Shadow_Skull, and the two PvP banners
    # for the faction each traitor turned their back on.
    "Hardcore PvP": dict(
        spell_id=900002, spellicon_id=3139,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Hardcore PvP",
        desc="You gain bonus experience and world mobs may drop dungeon gear for you. "
             "Killed by another Hardcore player, you lose part of what your bags hold.",
    ),
    "Traitor to the Alliance": dict(
        spell_id=900003, spellicon_id=1703,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Traitor to the Alliance",
        desc="You and every other traitor are hostile to each other, whatever your factions. "
             "The Alliance's own cities will not have you.",
    ),
    "Traitor to the Horde": dict(
        spell_id=900004, spellicon_id=1704,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Traitor to the Horde",
        desc="You and every other traitor are hostile to each other, whatever your factions. "
             "The Horde's own cities will not have you.",
    ),
    # War Mode, the middle risk mode. PvE deliberately has no aura of its own:
    # it is the absence of the other two, and an icon everybody carries is
    # noise. Ascension's own War Mode (84420) uses icon 7042, which is one of
    # theirs and does not exist here - 279 is this client's
    # Ability_Warrior_OffensiveStance, checked against its SpellIcon.dbc.
    "War Mode": dict(
        spell_id=900005, spellicon_id=279,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="War Mode",
        desc="Open world PvP is enabled and you earn bonus experience. Nothing you carry is "
             "ever taken from you - that is High-Risk.",
    ),
    # One per level band of the Hardcore PvP world drops
    # (mod_madosa_hardcore_pvp_loot.cpp). The band an aura names is the band the
    # drop actually rolls from - both come from the same LOOT_BANDS table - so
    # the tooltip cannot drift away from what the server does. Icons escalate
    # from a plain box to a chained chest so the change is visible at a glance.
    "Dungeon Spoils Levels 1-19": dict(
        spell_id=900010, spellicon_id=2492,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 1-19",
        desc="While Hardcore PvP is on, world mobs may drop gear from Ragefire Chasm, the Deadmines, Wailing Caverns and Shadowfang Keep. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 20-29": dict(
        spell_id=900011, spellicon_id=227,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 20-29",
        desc="While Hardcore PvP is on, world mobs may drop gear from Blackfathom Deeps, the Stockade, Gnomeregan and Razorfen Kraul. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 30-39": dict(
        spell_id=900012, spellicon_id=2930,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 30-39",
        desc="While Hardcore PvP is on, world mobs may drop gear from Scarlet Monastery, Razorfen Downs and Uldaman. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 40-49": dict(
        spell_id=900013, spellicon_id=3210,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 40-49",
        desc="While Hardcore PvP is on, world mobs may drop gear from Zul'Farrak, Maraudon and the Sunken Temple. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 50-59": dict(
        spell_id=900014, spellicon_id=4244,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 50-59",
        desc="While Hardcore PvP is on, world mobs may drop gear from Blackrock Depths, Lower Blackrock Spire and Dire Maul. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 60-69": dict(
        spell_id=900015, spellicon_id=3708,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 60-69",
        desc="While Hardcore PvP is on, world mobs may drop gear from Stratholme, Scholomance, Upper Blackrock Spire and Hellfire Citadel. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Levels 70-79": dict(
        spell_id=900016, spellicon_id=2677,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Levels 70-79",
        desc="While Hardcore PvP is on, world mobs may drop gear from Coilfang Reservoir, Auchindoun, Tempest Keep and Karazhan. "
             "The band moves on as you level.",
    ),
    "Dungeon Spoils Level 80": dict(
        spell_id=900017, spellicon_id=796,
        attributes=0x89800000, attributes_ex3=0x00100000,
        name="Dungeon Spoils: Level 80",
        desc="While Hardcore PvP is on, world mobs may drop gear from Northrend's dungeons, Naxxramas, Ulduar and Icecrown Citadel. "
             "The band moves on as you level.",
    ),
}

# Spell.dbc field indices (3.3.5a, 234 fields). Verified against known spells:
# 133 gives Fireball -> Spell_Fire_FlameBolt, 136 gives its English name.
F_SPELL_ICON, F_SPELL_NAME, F_SPELL_DESC = 133, 136, 170

# Field indices used to compose a brand new NEW_SPELLS row from scratch (see
# src/server/shared/DataStores/DBCStructure.h struct SpellEntry for the layout).
F_ATTRIBUTES, F_ATTRIBUTES_EX3 = 4, 7
F_CASTTIME, F_DURATION, F_RANGE = 28, 40, 46
F_EFFECT1, F_TARGET_A1, F_AURA1 = 71, 86, 95
F_SCHOOL_MASK = 225
SPELL_EFFECT_APPLY_AURA, TARGET_UNIT_CASTER, SPELL_AURA_DUMMY = 6, 1, 4
CASTTIME_INSTANT, RANGE_SELF, DURATION_INFINITE = 1, 1, 21

# EquippedItemClass. -1 means "no equipped item required"; 0 is NOT a neutral
# default, it means ITEM_CLASS_CONSUMABLE. Leaving it at 0 made every cast fail
# with SPELL_FAILED_EQUIPPED_ITEM_CLASS - silently, because a triggered cast
# reports nothing - since Player::HasItemFitToSpellRequirements() demands an
# equipped item of that class and consumables can never be equipped
# (Spell.cpp CheckItems -> Player.cpp:12786, Item.cpp:889). The aura itself was
# fine all along: applying it directly worked, only casting it did not.
F_EQUIPPED_ITEM_CLASS = 68
NO_EQUIPPED_ITEM_REQUIRED = 0xFFFFFFFF  # -1 as uint32

# The per-string locale mask that follows each 16-slot string block. Patched rows
# inherit a sane value from the spell they overwrite, but a row built from
# scratch would leave these at 0, which real spells never do.
F_NAME_FLAGS, F_DESC_FLAGS = 152, 186
STRING_LOCALE_MASK = 16712190  # what every stock 3.3.5a spell carries

# Template rows copied for anything we do not set ourselves, so sound, blood and
# the other fields stay plausible. 111 = Chicken model, 7920 = Mechanical Chicken.
TPL_MODELDATA, TPL_DISPLAYINFO = 111, 7920


def vanilla(name):
    """Server DBC as it was before we ever touched it."""
    bak = os.path.join(SERVER_DBC, name + ".bak-vanilla")
    return bak if os.path.exists(bak) else os.path.join(SERVER_DBC, name)


def client_base(name):
    """client_dbc() spilled to a file, because DBCBuilder reads from a path."""
    blob, source = client_dbc(name)
    path = os.path.join(OUT, "_base_" + name)
    open(path, "wb").write(blob)
    return path, source


def collect_files():
    """Pull every model file and icon out of the Ascension archives."""
    files, handles = [], {}
    for pet, c in PETS.items():
        arc = c["archive"]
        handles.setdefault(arc, MPQ(os.path.join(ASCENSION, arc)))
        m = handles[arc]
        folder = c["model"].rsplit("\\", 1)[0].lower() + "\\"
        listing = m.read_file("(listfile)").decode("ascii", "replace")
        names = [n.strip() for n in listing.replace("\r\n", "\n").split("\n") if n.strip()]
        got = [n for n in names if n.lower().startswith(folder)]
        if not got:
            raise SystemExit(f"{pet}: no files under {folder} in {arc}")
        for n in got:
            files.append((n, m.read_file(n)))
        ia = c["icon_archive"]
        handles.setdefault(ia, MPQ(os.path.join(ASCENSION, ia)))
        ip = "Interface\\Icons\\%s.blp" % c["icon"]
        blob = handles[ia].read_file(ip)
        if blob is None:
            raise SystemExit(f"{pet}: icon {ip} not found in {ia}")
        files.append((ip, blob))
        print(f"  {pet:14} {len(got):>3} model files + icon {c['icon']}")
    for label, c in NEW_SPELLS.items():
        if "icon" not in c:
            continue   # reuses an icon this client already has
        ia = c["icon_archive"]
        handles.setdefault(ia, MPQ(os.path.join(ASCENSION, ia)))
        ip = "Interface\\Icons\\%s.blp" % c["icon"]
        blob = handles[ia].read_file(ip)
        if blob is None:
            raise SystemExit(f"{label}: icon {ip} not found in {ia}")
        files.append((ip, blob))
        print(f"  {label:14}       icon {c['icon']}")
    return files


def build_creature_dbcs(models, base_model, base_display, quiet=False):
    """CreatureModelData + CreatureDisplayInfo: the given base plus our rows."""
    cmd = DBCBuilder(base_model)
    cdi = DBCBuilder(base_display)
    tpl_md = next(r for r in cmd.src.rows() if r[0] == TPL_MODELDATA)
    tpl_di = next(r for r in cdi.src.rows() if r[0] == TPL_DISPLAYINFO)
    for pet, c in PETS.items():
        blob = models[c["model"]]
        vb = struct.unpack_from("<6f", blob, 0xA0)   # vertex bounding box
        cb = struct.unpack_from("<6f", blob, 0xBC)   # collision box
        r = list(tpl_md)
        r[0] = c["modeldata_id"]
        r[2] = cmd.addstr(c["model"][:-3] + ".mdx")  # the client swaps .mdx for .m2
        r[14], r[15] = I(cb[3] - cb[0]), I(cb[5])
        for k in range(6):
            r[17 + k] = I(vb[k])
        cmd.append(r)
        e = list(tpl_di)
        e[0], e[1], e[4] = c["display_id"], c["modeldata_id"], I(c["dbc_scale"])
        e[6], e[7], e[8] = cdi.addstr(c["texture"]), 0, 0
        cdi.append(e)
        if not quiet:
            print(f"  {pet:14} model {c['modeldata_id']} display {c['display_id']} "
                  f"height {vb[5] * c['dbc_scale'] * c['display_scale']:.2f}")
    return cmd, cdi


def build_item_dbc(base):
    idi = DBCBuilder(base)
    src = DBC(base)
    tpl = next(r for r in src.rows() if r[0] == 59497)   # a plain, model-less item
    for pet, c in PETS.items():
        q = list(tpl)
        q[0], q[5] = c["itemdisplay_id"], idi.addstr(c["icon"])
        idi.append(q)
    return idi


def build_spell_dbcs(spell_blob, spell_from, icon_src, icon_from, quiet=False):
    """Patch icon/name/description of the six summon spells in place, then
    append the NEW_SPELLS rows (ids that do not exist in `spell_blob` yet).

    Spell.dbc is ~49 MB; parsing it into Python rows costs hundreds of megabytes
    of memory, so existing records are patched at byte level. New rows (for
    NEW_SPELLS) are built field-by-field instead, since there is no existing
    row to patch.

    Called once for the client's own Spell.dbc/SpellIcon.dbc and once for the
    server's, so a brand new spell id is recognised on both sides - the server
    must know the id too, or CastSpell(id) just fails there even though the
    client-side icon/tooltip would be fine.
    """
    if not quiet:
        print(f"  base Spell.dbc from {spell_from}, SpellIcon.dbc from {icon_from}")
    spell = bytearray(spell_blob)
    tmp_icon_src = os.path.join(OUT, "_SpellIcon.src.%s" % os.getpid())
    open(tmp_icon_src, "wb").write(icon_src)

    ib = DBCBuilder(tmp_icon_src)
    tpl = list(ib.src.row(0))
    for pet, c in PETS.items():
        r = list(tpl)
        r[0] = c["spellicon_id"]
        r[1] = ib.addstr("Interface\\Icons\\" + c["icon"])
        ib.append(r)
    for label, c in NEW_SPELLS.items():
        if "icon" not in c:
            continue   # spellicon_id already exists in this client's SpellIcon.dbc
        r = list(tpl)
        r[0] = c["spellicon_id"]
        r[1] = ib.addstr("Interface\\Icons\\" + c["icon"])
        ib.append(r)

    _, rc, fc, rs, sb = struct.unpack_from("<4sIIII", spell, 0)
    strings = bytearray(spell[20 + rc * rs:20 + rc * rs + sb])

    def addstr(s):
        off = len(strings)
        strings.extend(s.encode("latin1") + b"\x00")
        return off

    by_spell = {c["spell"]: (pet, c) for pet, c in PETS.items()}
    done = 0
    extra_done = 0
    for i in range(rc):
        off = 20 + i * rs
        sid = struct.unpack_from("<I", spell, off)[0]
        if sid in by_spell:
            pet, c = by_spell[sid]
            struct.pack_into("<I", spell, off + F_SPELL_ICON * 4, c["spellicon_id"])
            struct.pack_into("<I", spell, off + F_SPELL_NAME * 4, addstr(c["spell_name"]))
            struct.pack_into("<I", spell, off + F_SPELL_DESC * 4, addstr(c["spell_desc"]))
            done += 1
            if not quiet:
                print(f"  {pet:14} spell {sid} icon/name/description patched")
        elif sid in EXTRA_SPELLS:
            e = EXTRA_SPELLS[sid]
            struct.pack_into("<I", spell, off + F_SPELL_NAME * 4, addstr(e["name"]))
            struct.pack_into("<I", spell, off + F_SPELL_DESC * 4, addstr(e["desc"]))
            extra_done += 1
            if not quiet:
                print(f"  {e['name']:14} spell {sid} name/description patched")
    if done != len(PETS):
        raise SystemExit(f"only {done}/{len(PETS)} pet spells found in Spell.dbc")
    if extra_done != len(EXTRA_SPELLS):
        raise SystemExit(f"only {extra_done}/{len(EXTRA_SPELLS)} extra spells found")

    new_rows = bytearray()
    for label, c in NEW_SPELLS.items():
        row = [0] * fc
        row[0] = c["spell_id"]
        row[F_ATTRIBUTES] = c.get("attributes", 0)
        row[F_ATTRIBUTES_EX3] = c.get("attributes_ex3", 0)
        row[F_CASTTIME] = CASTTIME_INSTANT
        row[F_DURATION] = DURATION_INFINITE
        row[F_RANGE] = RANGE_SELF
        row[F_EFFECT1] = SPELL_EFFECT_APPLY_AURA
        row[F_TARGET_A1] = TARGET_UNIT_CASTER
        row[F_AURA1] = SPELL_AURA_DUMMY
        row[F_SPELL_ICON] = c["spellicon_id"]
        row[F_SPELL_NAME] = addstr(c["name"])
        row[F_SPELL_DESC] = addstr(c["desc"])
        row[F_SCHOOL_MASK] = 1  # physical; unused by a dummy aura, kept non-zero
        row[F_EQUIPPED_ITEM_CLASS] = NO_EQUIPPED_ITEM_REQUIRED
        row[F_NAME_FLAGS] = STRING_LOCALE_MASK
        row[F_DESC_FLAGS] = STRING_LOCALE_MASK
        new_rows += struct.pack("<%dI" % fc, *row)
        if not quiet:
            print(f"  {label:14} spell {c['spell_id']} created (icon {c['spellicon_id']})")
    total_rc = rc + len(NEW_SPELLS)

    head = struct.pack("<4sIIII", b"WDBC", total_rc, fc, rs, len(strings))
    out = head + bytes(spell[20:20 + rc * rs]) + bytes(new_rows) + bytes(strings)
    os.remove(tmp_icon_src)
    return out, ib


def emit_sql():
    lines = ["-- Generated by tools/clientpatch/build_patches.py - do not hand-edit.",
             "-- The display IDs only exist in the client patches this script builds.",
             ""]
    for pet, c in PETS.items():
        lines.append(f"-- {pet}")
        lines.append("UPDATE `creature_template_model` SET `CreatureDisplayID` = "
                     f"{c['display_id']}, `DisplayScale` = {c['display_scale']} "
                     f"WHERE `CreatureID` = {c['creature']} AND `Idx` = 0;")
        lines.append(f"UPDATE `item_template` SET `displayid` = {c['itemdisplay_id']} "
                     f"WHERE `entry` = {c['item']};")
    lines += ["", "-- Without a creature_model_info row Creature::InitEntry aborts and the",
              "-- pet never spawns. Its error names creature_template_model - wrong table.",
              "DELETE FROM `creature_model_info` WHERE `DisplayID` IN (%s);"
              % ",".join(str(c["display_id"]) for c in PETS.values()),
              "INSERT INTO `creature_model_info` (`DisplayID`,`BoundingRadius`,"
              "`CombatReach`,`Gender`,`DisplayID_Other_Gender`) VALUES"]
    # The trailing comment must come after the separator, otherwise "--" swallows it.
    items = list(PETS.items())
    for n, (pet, c) in enumerate(items):
        sep = ";" if n == len(items) - 1 else ","
        lines.append(f"({c['display_id']},{c['model_info'][0]},{c['model_info'][1]},"
                     f"{c['model_info'][2]},0){sep}   -- {pet}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true",
                    help="copy the results into the client and server")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)

    if args.install and os.popen("pgrep -if 'wow\\.exe'").read().strip():
        raise SystemExit("The WoW client is running. Close it first - it rewrites "
                         "Cache/WDB/*.wdb from memory on exit and would undo the "
                         "cache clear below.")

    print("Collecting assets from Ascension:")
    files = collect_files()
    models = {c["model"]: dict(files)[c["model"]] for c in PETS.values()}

    # Two different bases on purpose. The client must keep whatever its enabled
    # patches already changed - the HD model pack adds 206 CreatureModelData rows
    # and rewrites CreatureDisplayInfo texture paths, and overwriting that with
    # the server's plain copy is what turned HD creatures into green blobs. The
    # server keeps its own extracted DBCs so its collision and bounding data stay
    # exactly as the maps were built against. Both get the same appended rows.
    print("Building creature DBCs (client, on top of the client's own DBCs):")
    b_cmd, from_cmd = client_base("CreatureModelData.dbc")
    b_cdi, from_cdi = client_base("CreatureDisplayInfo.dbc")
    b_idi, from_idi = client_base("ItemDisplayInfo.dbc")
    print(f"  base CreatureModelData.dbc from {from_cmd}, "
          f"CreatureDisplayInfo.dbc from {from_cdi}, ItemDisplayInfo.dbc from {from_idi}")
    cmd, cdi = build_creature_dbcs(models, b_cmd, b_cdi)
    idi = build_item_dbc(b_idi)

    print("Building creature DBCs (server, on top of the server's own DBCs):")
    s_cmd, s_cdi = build_creature_dbcs(models, vanilla("CreatureModelData.dbc"),
                                       vanilla("CreatureDisplayInfo.dbc"), quiet=True)
    s_idi = build_item_dbc(vanilla("ItemDisplayInfo.dbc"))

    print("Patching spells (client, on top of the client's own Spell.dbc):")
    c_spell_blob, c_spell_from = client_dbc("Spell.dbc")
    c_icon_blob, c_icon_from = client_dbc("SpellIcon.dbc")
    spell_blob, ib = build_spell_dbcs(c_spell_blob, c_spell_from, c_icon_blob, c_icon_from)

    print("Patching spells (server, on top of the server's own Spell.dbc):")
    s_spell_blob = open(vanilla("Spell.dbc"), "rb").read()
    s_icon_blob = open(vanilla("SpellIcon.dbc"), "rb").read()
    s_spell_out, s_ib = build_spell_dbcs(s_spell_blob, "server", s_icon_blob, "server", quiet=True)

    p_cmd = os.path.join(OUT, "client_CreatureModelData.dbc")
    p_cdi = os.path.join(OUT, "client_CreatureDisplayInfo.dbc")
    p_idi = os.path.join(OUT, "client_ItemDisplayInfo.dbc")
    p_ico = os.path.join(OUT, "client_SpellIcon.dbc")
    cmd.save(p_cmd); cdi.save(p_cdi); idi.save(p_idi); ib.save(p_ico)
    s_cmd.save(os.path.join(OUT, "CreatureModelData.dbc"))
    s_cdi.save(os.path.join(OUT, "CreatureDisplayInfo.dbc"))
    s_idi.save(os.path.join(OUT, "ItemDisplayInfo.dbc"))
    s_ib.save(os.path.join(OUT, "SpellIcon.dbc"))
    open(os.path.join(OUT, "Spell.dbc"), "wb").write(s_spell_out)
    for name in ("CreatureModelData.dbc", "CreatureDisplayInfo.dbc", "ItemDisplayInfo.dbc"):
        stale = os.path.join(OUT, "_base_" + name)
        if os.path.exists(stale):
            os.remove(stale)

    size, _ = build(os.path.join(OUT, "patch-v.mpq"), files)
    print(f"patch-v.mpq       {size / 1024 / 1024:6.1f} MB  ({len(files)} files)")
    dbcs = [("DBFilesClient\\CreatureModelData.dbc", open(p_cmd, "rb").read()),
            ("DBFilesClient\\CreatureDisplayInfo.dbc", open(p_cdi, "rb").read()),
            ("DBFilesClient\\ItemDisplayInfo.dbc", open(p_idi, "rb").read()),
            ("DBFilesClient\\SpellIcon.dbc", open(p_ico, "rb").read()),
            ("DBFilesClient\\Spell.dbc", spell_blob)]
    size, _ = build(os.path.join(OUT, "patch-enus-y.mpq"), dbcs)
    print(f"patch-enus-y.mpq  {size / 1024 / 1024:6.1f} MB  (5 DBCs)")

    # Read both archives back and compare byte for byte before shipping them.
    for path, expect in ((os.path.join(OUT, "patch-v.mpq"), files),
                         (os.path.join(OUT, "patch-enus-y.mpq"), dbcs)):
        m = MPQ(path)
        bad = [n for n, blob in expect if m.read_file(n) != blob]
        if bad:
            raise SystemExit(f"{os.path.basename(path)}: round-trip failed for {bad[:3]}")
    print("Round-trip verified for both archives.")

    sql = emit_sql()
    open(os.path.join(OUT, "pet_ascension_models.sql"), "w").write(sql)

    if args.install:
        shutil.copy(os.path.join(OUT, "patch-v.mpq"), os.path.join(CLIENT, "data/patch-v.mpq"))
        shutil.copy(os.path.join(OUT, "patch-enus-y.mpq"),
                    os.path.join(CLIENT, "data/enus/patch-enus-y.mpq"))
        for n in ("CreatureModelData.dbc", "CreatureDisplayInfo.dbc", "ItemDisplayInfo.dbc",
                  "SpellIcon.dbc", "Spell.dbc"):
            bak = os.path.join(SERVER_DBC, n + ".bak-vanilla")
            if not os.path.exists(bak):
                shutil.copy(os.path.join(SERVER_DBC, n), bak)
            shutil.copy(os.path.join(OUT, n), os.path.join(SERVER_DBC, n))
        wdb = os.path.join(CLIENT, "Cache/WDB/enUS")
        removed = 0
        for f in os.listdir(wdb) if os.path.isdir(wdb) else []:
            if f.endswith(".wdb"):
                os.remove(os.path.join(wdb, f)); removed += 1
        print(f"Installed. Cleared {removed} cached .wdb files.")
        print("Now: apply out/pet_ascension_models.sql, restart worldserver, start client.")
    else:
        print(f"Wrote {OUT}. Re-run with --install to deploy.")


if __name__ == "__main__":
    main()
