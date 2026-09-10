#!/usr/bin/env python3
"""Give Craftbot every recipe a profession has, not just the trainer ones.

Craftbot (see data/sql/db-world/base/profession_trainer_pet.sql) is trainer
90002, a union of every profession trainer's list. That is exactly why it has
gaps: trainers only know trainer recipes. Everything else a profession can
learn - vendor recipes, world drops, reputation rewards, the Expert/Artisan/
Master books for First Aid and Cooking - reaches the player as a recipe item
(item_template.class = 9) that teaches a spell on use. This script turns
those items into trainer_spell rows for 90002, so the rank chain and the
recipe list are complete without a single quest, book or vendor trip.

Which spell an item teaches is not written in one place:

  * most recipes carry it in spellid_2 with spelltrigger_2 = 6
    (ITEM_SPELLTRIGGER_LEARN_SPELL_ID), spellid_1 being the generic
    "Learning" wrapper (483);
  * the profession-rank books and a few dozen others only have a learn spell
    in spellid_1 (SPELL_EFFECT_LEARN_SPELL, 36) whose EffectTriggerSpell is
    the real thing - that needs Spell.dbc.

Both paths are resolved here, then the taught spell is checked against
SkillLineAbility.dbc for the item's RequiredSkill, which weeds out the
handful of items that point at spells no longer on their skill line. Class
spellbooks (Tome/Codex/Libram, RequiredSkill 0) and Blizzard's own scrap
("Deprecated ...", "[PH]") are skipped.

Requirements come from the item: ReqSkillLine/ReqSkillRank from
RequiredSkill/RequiredSkillRank, ReqAbility1 from RequiredSpell (the
specialisation gates - Weaponsmith, Dragonscale, Gnomish, ...). The core's
trainer code then does the rest at display and purchase time: rank chains
via GetPrevSpellInChain(), class/race fit, the two-primary-professions cap.

MoneyCost is 0 by request. INSERT IGNORE keeps whatever profession_trainer_pet.sql
already put on 90002 for the same spell (39 overlaps), so re-running is safe
and the trainer rows stay authoritative for those.

Output: data/sql/db-world/base/profession_trainer_pet_recipes.sql. The name
sorts after profession_trainer_pet.sql on purpose: that file starts with
DELETE FROM trainer_spell WHERE TrainerId = 90002, and the updater applies
base files in name order.

    ./gen.py --password <world db password>
"""

import argparse
import os
import re
import struct
import subprocess
import sys
from collections import defaultdict

TRAINER_ID = 90002
SPELL_EFFECT_LEARN_SPELL = 36
ITEM_SPELLTRIGGER_LEARN_SPELL_ID = 6
ITEM_CLASS_RECIPE = 9

# Blizzard's scratch entries. The ITEM_FLAG_DEPRECATED bit is not usable for
# this - it sits on perfectly real Runecloth patterns and Northrend designs.
SCRAP = re.compile(r'deprecated|\[ph\]|^test\b|\btest\b|monster -', re.I)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(
    HERE, '..', '..', 'data', 'sql', 'db-world', 'base', 'profession_trainer_pet_recipes.sql'))


class World:
    def __init__(self, host, user, password, database):
        self._base = ['mysql', '-h' + host, '-u' + user, '-N', '-B',
                      '--default-character-set=utf8mb4', database]
        self._env = dict(os.environ, MYSQL_PWD=password)

    def rows(self, sql):
        proc = subprocess.run(self._base + ['-e', sql], capture_output=True, text=True,
                              env=self._env)
        if proc.returncode:
            raise SystemExit('mysql: ' + proc.stderr.strip())
        for line in proc.stdout.splitlines():
            if line:
                yield line.split('\t')


# --------------------------------------------------------------------------
# DBC
# --------------------------------------------------------------------------

def read_dbc(path, fields):
    with open(path, 'rb') as f:
        magic, nrec, nfield, recsize, strsize = struct.unpack('<4sIIII', f.read(20))
        if magic != b'WDBC':
            raise SystemExit('%s: not a DBC' % path)
        if nfield != fields:
            raise SystemExit('%s: %d fields, expected %d (wrong client version?)'
                             % (path, nfield, fields))
        data = f.read(nrec * recsize)
    for i in range(nrec):
        yield struct.unpack_from('<%dI' % nfield, data, i * recsize)


def learned_spells(dbc_dir):
    """spell id -> spells it teaches via SPELL_EFFECT_LEARN_SPELL (3.3.5 Spell.dbc)."""
    EFFECT, TRIGGER = 71, 116
    taught = {}
    for r in read_dbc(os.path.join(dbc_dir, 'Spell.dbc'), 234):
        t = [r[TRIGGER + k] for k in range(3)
             if r[EFFECT + k] == SPELL_EFFECT_LEARN_SPELL and r[TRIGGER + k]]
        if t:
            taught[r[0]] = t
    return taught


def skill_spells(dbc_dir):
    """skill line -> set of spell ids on it (3.3.5 SkillLineAbility.dbc)."""
    SKILL, SPELL = 1, 2
    by_skill = defaultdict(set)
    for r in read_dbc(os.path.join(dbc_dir, 'SkillLineAbility.dbc'), 14):
        by_skill[r[SKILL]].add(r[SPELL])
    return by_skill


# --------------------------------------------------------------------------
# Items -> trainer rows
# --------------------------------------------------------------------------

def taught_by(item, teaches):
    entry, name, sp1, tr1, sp2, tr2 = item[:6]
    if tr2 == ITEM_SPELLTRIGGER_LEARN_SPELL_ID and sp2:
        return sp2
    if sp1 in teaches and len(teaches[sp1]) == 1:
        return teaches[sp1][0]
    return 0


def collect(world, dbc_dir):
    teaches = learned_spells(dbc_dir)
    on_skill = skill_spells(dbc_dir)

    sql = ('SELECT entry, name, spellid_1, spelltrigger_1, spellid_2, spelltrigger_2, '
           'RequiredSkill, RequiredSkillRank, RequiredSpell '
           'FROM item_template WHERE class = %d ORDER BY entry' % ITEM_CLASS_RECIPE)

    rows = {}         # spell -> (skill, rank, req_spell, item entry, item name)
    stats = defaultdict(int)
    for raw in world.rows(sql):
        entry, name = int(raw[0]), raw[1]
        sp1, tr1, sp2, tr2, skill, rank, req = (int(x) for x in raw[2:9])
        if not skill:
            stats['class spellbook'] += 1
            continue
        if SCRAP.search(name):
            stats['scrap name'] += 1
            continue
        spell = taught_by((entry, name, sp1, tr1, sp2, tr2), teaches)
        if not spell:
            stats['teaches nothing'] += 1
            continue
        if spell not in on_skill.get(skill, ()):
            stats['spell not on its skill line'] += 1
            continue
        if spell in rows:
            # Alliance/Horde twins, vendor vs. drop copies: one row per spell,
            # keep the lowest requirement seen.
            old = rows[spell]
            if rank < old[1]:
                rows[spell] = (skill, rank, req, entry, name)
            stats['duplicate spell'] += 1
            continue
        rows[spell] = (skill, rank, req, entry, name)
    return rows, stats


def write_sql(rows, path):
    by_skill = defaultdict(list)
    for spell, (skill, rank, req, entry, name) in rows.items():
        by_skill[skill].append((rank, spell, req, entry, name))

    out = []
    out.append('-- Generated by tools/craftbotgen/gen.py - do not edit by hand.\n')
    out.append('--\n')
    out.append('-- Every recipe item (item_template.class = 9) turned into a Craftbot\n')
    out.append('-- (trainer %d) row, so vendor, drop, reputation and book recipes -\n' % TRAINER_ID)
    out.append('-- including the Expert/Artisan/Master First Aid and Cooking ranks - are\n')
    out.append('-- trainable there without the quest, the book or the vendor trip. Free.\n')
    out.append('-- INSERT IGNORE: rows profession_trainer_pet.sql already put here win.\n')
    out.append('-- Sorts after that file on purpose, since it starts with a DELETE.\n')
    out.append('\n')
    out.append('INSERT IGNORE INTO `trainer_spell` (`TrainerId`,`SpellId`,`MoneyCost`,`ReqSkillLine`,'
               '`ReqSkillRank`,`ReqAbility1`,`ReqAbility2`,`ReqAbility3`,`ReqLevel`) VALUES\n')
    values = []
    for skill in sorted(by_skill):
        for rank, spell, req, entry, name in sorted(by_skill[skill]):
            comment = name.replace('*/', '* /')
            values.append('(%d,%d,0,%d,%d,%d,0,0,0) /* %s */'
                          % (TRAINER_ID, spell, skill, rank, req, comment))
    out.append(',\n'.join(values))
    out.append(';\n')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dbc', default=os.path.expanduser('~/azerothcore/env/dist/data/dbc'))
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--user', default='acore')
    ap.add_argument('--password', default='acore')
    ap.add_argument('--db', default='acore_world')
    ap.add_argument('--out', default=OUT)
    args = ap.parse_args()

    world = World(args.host, args.user, args.password, args.db)
    rows, stats = collect(world, args.dbc)

    per_skill = defaultdict(int)
    for skill, *_ in rows.values():
        per_skill[skill] += 1
    print('recipes: %d' % len(rows))
    for skill in sorted(per_skill):
        print('  skill %-4d %d' % (skill, per_skill[skill]))
    for what, n in sorted(stats.items()):
        print('skipped, %s: %d' % (what, n))

    write_sql(rows, args.out)
    print('wrote %s' % args.out)


if __name__ == '__main__':
    main()
