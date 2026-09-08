#!/usr/bin/env python3
"""Generate pfQuest's missing WotLK database out of an AzerothCore world DB.

pfQuest ships Vanilla data dumped from VMaNGOS and TBC data from CMaNGOS, and
stops there: the addon runs on a 3.3.5 client but knows nothing north of
Outland. Its loader already looks for a "-wotlk" layer -

    for _, exp in pairs({ "-tbc", "-wotlk" }) do
      if pfDB[db]["data"..exp] then patchtable(pfDB[db]["data"], ...) end

- so the gap is data, not code. This writes that layer from the server the
addon is actually going to be used against, which means the spawns match the
realm, Playerbot changes and all.

What is generated, and why that set: everything pfQuest does not already have
an id for. A quest it already knows keeps the hand-checked entry it shipped
with; anything else - all of Northrend, the Death Knight start, the WotLK
instances, and whatever a private realm has added - comes from the database.

Coordinates. A spawn is a world position on a map; pfQuest wants a percentage
inside a zone. WorldMapArea.dbc gives every zone a rectangle in world
coordinates, and the conversion is

    x% = (locLeft - worldY) / (locLeft - locRight) * 100
    y% = (locTop  - worldX) / (locTop  - locBottom) * 100

which was checked against pfQuest's own TBC coordinates before this was
written: nine of ten sampled spawns land within 0.1% of the value the addon
ships, and the tenth is a spawn AzerothCore places differently from CMaNGOS.

Usage:
    gen.py --addon <pfQuest dir> [--dbc <dir>] [--db acore_world] [--dry-run]
"""
import argparse
import os
import re
import struct
import subprocess
import sys
from collections import defaultdict

# --------------------------------------------------------------------------
# DBC
# --------------------------------------------------------------------------

class DBC:
    def __init__(self, path):
        blob = open(path, 'rb').read()
        magic, self.count, self.fields, self.recsize, strsize = struct.unpack_from('<4sIIII', blob, 0)
        if magic != b'WDBC':
            raise ValueError('%s is not a DBC' % path)
        self._blob, self._base = blob, 20
        self._strings = blob[20 + self.count * self.recsize:][:strsize]

    def rows(self):
        for i in range(self.count):
            yield self._base + i * self.recsize

    def uints(self, offset, count=1):
        return struct.unpack_from('<%dI' % count, self._blob, offset)

    def floats(self, offset, count=1):
        return struct.unpack_from('<%df' % count, self._blob, offset)

    def string(self, offset):
        o = struct.unpack_from('<I', self._blob, offset)[0]
        if not o:
            return ''
        return self._strings[o:self._strings.index(b'\0', o)].decode('utf-8', 'replace')


def read_maps(dbc_dir):
    """areaID -> (mapID, left, right, top, bottom, area in yards^2)."""
    wma = DBC(os.path.join(dbc_dir, 'WorldMapArea.dbc'))
    out = {}
    for o in wma.rows():
        _, map_id, area_id = wma.uints(o, 3)
        left, right, top, bottom = wma.floats(o + 16, 4)
        if not area_id or left <= right or top <= bottom:
            continue                     # continents and mapless entries
        out[area_id] = (map_id, left, right, top, bottom,
                        (left - right) * (top - bottom))
    return out


def read_area_names(dbc_dir):
    """AreaTable.ID -> localised area name (field 11 is AreaName_lang enUS)."""
    area = DBC(os.path.join(dbc_dir, 'AreaTable.dbc'))
    return {area.uints(o)[0]: area.string(o + 11 * 4) for o in area.rows()}


# --------------------------------------------------------------------------
# The world database
# --------------------------------------------------------------------------

class World:
    def __init__(self, host, user, password, database):
        self._base = ['mysql', '-h' + host, '-u' + user, '-p' + password,
                      '-N', '-B', '--default-character-set=utf8mb4', database]

    def rows(self, sql):
        proc = subprocess.run(self._base + ['-e', sql], capture_output=True, text=True)
        if proc.returncode:
            raise SystemExit('mysql: ' + proc.stderr.strip())
        for line in proc.stdout.splitlines():
            if line:
                yield line.split('\t')


# A world database keeps quests the game never shipped: placeholders, retired
# text, Blizzard's own scratch entries. pfQuest's hand-curated data has none of
# them and neither should this.
SCRAP = re.compile(r'unused|deprecated|\bnyi\b|placeholder|\[ph\]|^test\b|^<', re.I)


def is_scrap(title):
    title = (title or '').strip()
    return not title or bool(SCRAP.search(title))


def num(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        try:
            return float(value)
        except (TypeError, ValueError):
            return default


# --------------------------------------------------------------------------
# What pfQuest already knows
# --------------------------------------------------------------------------

ID_KEY = re.compile(r'\[(\d+)\]\s*=')


def known_ids(addon, *files):
    """The top-level ids in a pfQuest data file, without executing it."""
    ids = set()
    for name in files:
        path = os.path.join(addon, name)
        if not os.path.exists(path):
            continue
        text = open(path, encoding='utf-8', errors='replace').read()
        body = text.split('=', 1)[1] if '=' in text else text
        depth = 0
        for match in re.finditer(r'\[(\d+)\]\s*=|[{}]', body):
            token = match.group(0)
            if token == '{':
                depth += 1
            elif token == '}':
                depth -= 1
            elif depth == 1:
                ids.add(int(match.group(1)))
    return ids


# --------------------------------------------------------------------------
# Lua output
# --------------------------------------------------------------------------

def lua_string(s):
    return '"%s"' % (s or '').replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ')


def fmt(v):
    if isinstance(v, float):
        text = ('%.2f' % v).rstrip('0').rstrip('.')
        return text or '0'
    return str(v)


def write_table(path, assignment, entries, header):
    """entries: list of (key, rendered value)."""
    with open(path, 'w', encoding='utf-8') as fh:
        for line in header:
            fh.write('-- ' + line + '\n')
        fh.write('\n%s={' % assignment)
        for key, value in entries:
            fh.write('[%d]=%s,' % (key, value))
        fh.write('}\n')
    return len(entries)


# --------------------------------------------------------------------------
# Building the layer
# --------------------------------------------------------------------------

class Generator:
    def __init__(self, world, maps, area_names, addon):
        self.world, self.maps, self.area_names, self.addon = world, maps, area_names, addon
        self.by_map = defaultdict(list)
        for area_id, (map_id, l, r, t, b, size) in maps.items():
            self.by_map[map_id].append((size, area_id, l, r, t, b))
        for entries in self.by_map.values():
            entries.sort()                       # smallest rectangle wins

    def locate(self, map_id, x, y):
        """(zone id, x%, y%) for a world position, or None if off every map."""
        for _, area_id, l, r, t, b in self.by_map.get(map_id, ()):
            if r <= y <= l and b <= x <= t:
                return area_id, (l - y) / (l - r) * 100.0, (t - x) / (t - b) * 100.0
        return None

    # -- spawns ------------------------------------------------------------

    def spawns(self, table):
        """entry -> [ (x%, y%, zone, respawn), ... ], only inside known zones."""
        out = defaultdict(list)
        seen = defaultdict(set)
        sql = ("SELECT id, map, position_x, position_y, spawntimesecs FROM %s" % table)
        for row in self.world.rows(sql):
            entry, map_id = int(row[0]), int(row[1])
            here = self.locate(map_id, float(row[2]), float(row[3]))
            if not here:
                continue
            zone, px, py = here
            key = (round(px, 1), round(py, 1), zone)
            if key in seen[entry]:
                continue                          # duplicate spawn point
            seen[entry].add(key)
            out[entry].append((round(px, 1), round(py, 1), zone, num(row[4])))
        return out

    # -- quests ------------------------------------------------------------

    def quests(self, skip):
        quests, wanted_units, wanted_objects, wanted_items = {}, set(), set(), set()

        addon_rows = {int(r[0]): r for r in self.world.rows(
            "SELECT ID, AllowableClasses, PrevQuestID FROM quest_template_addon")}

        columns = ("ID, QuestLevel, MinLevel, AllowableRaces, StartItem,"
                   "RequiredNpcOrGo1, RequiredNpcOrGo2, RequiredNpcOrGo3, RequiredNpcOrGo4,"
                   "RequiredItemId1, RequiredItemId2, RequiredItemId3,"
                   "RequiredItemId4, RequiredItemId5, RequiredItemId6, LogTitle")
        for row in self.world.rows("SELECT %s FROM quest_template" % columns):
            qid = int(row[0])
            if qid in skip or is_scrap(row[15] if len(row) > 15 else ''):
                continue
            entry = {'lvl': num(row[1]), 'min': num(row[2])}
            races = num(row[3])
            if races:
                entry['race'] = races
            extra = addon_rows.get(qid)
            if extra:
                classes = num(extra[1])
                if classes:
                    entry['class'] = classes
                prev = num(extra[2])
                if prev > 0:
                    entry['pre'] = [prev]

            objectives = defaultdict(set)
            for value in row[5:9]:
                value = num(value)
                if value > 0:
                    objectives['U'].add(value)
                    wanted_units.add(value)
                elif value < 0:
                    objectives['O'].add(-value)
                    wanted_objects.add(-value)
            for value in row[9:15]:
                value = num(value)
                if value > 0:
                    objectives['I'].add(value)
                    wanted_items.add(value)
            if objectives:
                entry['obj'] = objectives

            start_item = num(row[4])
            if start_item > 0:
                entry.setdefault('start', defaultdict(set))['I'].add(start_item)
                wanted_items.add(start_item)
            quests[qid] = entry

        relations = [
            ('creature_queststarter', 'start', 'U', wanted_units),
            ('creature_questender', 'end', 'U', wanted_units),
            ('gameobject_queststarter', 'start', 'O', wanted_objects),
            ('gameobject_questender', 'end', 'O', wanted_objects),
        ]
        for table, side, kind, sink in relations:
            for row in self.world.rows("SELECT quest, id FROM %s" % table):
                qid, entry_id = int(row[0]), int(row[1])
                if qid not in quests:
                    continue
                quests[qid].setdefault(side, defaultdict(set))[kind].add(entry_id)
                sink.add(entry_id)

        # a quest with no giver, no turn-in and no objective draws nothing
        empty = [q for q, e in quests.items()
                 if not e.get('start') and not e.get('end') and not e.get('obj')]
        for q in empty:
            del quests[q]

        return quests, wanted_units, wanted_objects, wanted_items

    # -- item sources ------------------------------------------------------

    def item_sources(self, items):
        """item -> { 'U': {creature: chance}, 'O': {object: chance}, 'V': {vendor: 0} }"""
        if not items:
            return {}
        wanted = set(items)
        out = defaultdict(lambda: defaultdict(dict))

        # reference loot, resolved one level deep the way the core does
        refs = defaultdict(list)
        for row in self.world.rows(
                "SELECT Entry, Item, Chance FROM reference_loot_template"):
            refs[int(row[0])].append((int(row[1]), num(row[2])))

        for table, kind in (('creature_loot_template', 'U'),
                            ('gameobject_loot_template', 'O')):
            sql = "SELECT Entry, Item, Reference, Chance FROM %s" % table
            for row in self.world.rows(sql):
                source, item, reference, chance = (int(row[0]), int(row[1]),
                                                   int(row[2]), num(row[3]))
                if reference > 0:
                    for ref_item, ref_chance in refs.get(reference, ()):
                        if ref_item in wanted:
                            out[ref_item][kind][source] = round(
                                max(out[ref_item][kind].get(source, 0), ref_chance), 2)
                elif item in wanted:
                    out[item][kind][source] = round(
                        max(out[item][kind].get(source, 0), chance), 2)

        for row in self.world.rows("SELECT entry, item FROM npc_vendor"):
            vendor, item = int(row[0]), int(row[1])
            if item in wanted:
                out[item]['V'][vendor] = 0
        return out


# --------------------------------------------------------------------------
# Rendering, in pfQuest's own shapes
# --------------------------------------------------------------------------

def render_coords(coords):
    parts = ['[%d]={%s,%s,%d,%d},' % (i + 1, fmt(c[0]), fmt(c[1]), c[2], c[3])
             for i, c in enumerate(coords)]
    return '{' + ''.join(parts) + '}'


def render_unit(coords, level):
    body = '["coords"]=%s,' % render_coords(coords)
    if level:
        body += '["lvl"]=%s,' % lua_string(level)
    return '{' + body + '}'


def render_object(coords):
    return '{["coords"]=%s,}' % render_coords(coords)


def render_quest(entry):
    parts = []
    if entry.get('lvl'):
        parts.append('["lvl"]=%d,' % entry['lvl'])
    if entry.get('min'):
        parts.append('["min"]=%d,' % entry['min'])
    for side in ('start', 'end', 'obj'):
        block = entry.get(side)
        if not block:
            continue
        inner = ''.join('["%s"]={%s},' % (kind, ','.join(str(i) for i in sorted(ids)))
                        for kind, ids in sorted(block.items()) if ids)
        if inner:
            parts.append('["%s"]={%s},' % (side, inner))
    if entry.get('race'):
        parts.append('["race"]=%d,' % entry['race'])
    if entry.get('class'):
        parts.append('["class"]=%d,' % entry['class'])
    if entry.get('pre'):
        parts.append('["pre"]={%s},' % ','.join(str(i) for i in entry['pre']))
    return '{' + ''.join(parts) + '}'


def render_item(sources):
    parts = []
    for kind in ('U', 'O', 'V'):
        block = sources.get(kind)
        if not block:
            continue
        inner = ''.join('[%d]=%s,' % (src, fmt(chance)) for src, chance in sorted(block.items()))
        parts.append('["%s"]={%s},' % (kind, inner))
    return '{' + ''.join(parts) + '}'


HEADER = [
    'Generated by tools/pfquestgen/gen.py from this realm\'s acore_world.',
    'pfQuest ships Vanilla and TBC data only; this is the "-wotlk" layer its',
    'loader already looks for, built from the server the addon runs against,',
    'so the spawns are the ones this realm actually has.',
    'Do not edit by hand - regenerate instead.',
]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--addon', required=True, help='the pfQuest-wotlk directory')
    ap.add_argument('--dbc', default=os.path.expanduser(
        '~/azerothcore/env/dist/data/dbc'))
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--user', default='acore')
    ap.add_argument('--password', default='acore')
    ap.add_argument('--db', default='acore_world')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    world = World(args.host, args.user, args.password, args.db)
    maps = read_maps(args.dbc)
    area_names = read_area_names(args.dbc)
    gen = Generator(world, maps, area_names, args.addon)

    print('zones with a world map rectangle: %d' % len(maps))

    have_quests = known_ids(args.addon, 'db/quests.lua', 'db/quests-tbc.lua')
    have_units = known_ids(args.addon, 'db/units.lua', 'db/units-tbc.lua')
    have_objects = known_ids(args.addon, 'db/objects.lua', 'db/objects-tbc.lua')
    have_items = known_ids(args.addon, 'db/items.lua', 'db/items-tbc.lua')
    have_zones = known_ids(args.addon, 'db/enUS/zones.lua', 'db/enUS/zones-tbc.lua')
    have_minimap = known_ids(args.addon, 'db/minimap.lua', 'db/minimap-tbc.lua')
    print('pfQuest already has: %d quests, %d units, %d objects, %d items, %d zone names'
          % (len(have_quests), len(have_units), len(have_objects), len(have_items),
             len(have_zones)))

    quests, want_units, want_objects, want_items = gen.quests(have_quests)
    print('new quests: %d' % len(quests))

    creature_spawns = gen.spawns('creature')
    object_spawns = gen.spawns('gameobject')
    print('spawn points placed: %d creatures, %d objects'
          % (sum(len(v) for v in creature_spawns.values()),
             sum(len(v) for v in object_spawns.values())))

    # a unit or object is new if pfQuest lacks it and it either stands in a
    # zone pfQuest does not know or a new quest points at it
    new_zone = lambda coords: any(c[2] not in have_zones for c in coords)
    units = {u: c for u, c in creature_spawns.items()
             if u not in have_units and (new_zone(c) or u in want_units)}
    objects = {o: c for o, c in object_spawns.items()
               if o not in have_objects and (new_zone(c) or o in want_objects)}
    for u in want_units:
        units.setdefault(u, creature_spawns.get(u, []))
    for o in want_objects:
        objects.setdefault(o, object_spawns.get(o, []))
    units = {u: c for u, c in units.items() if u not in have_units}
    objects = {o: c for o, c in objects.items() if o not in have_objects}
    print('new units: %d, new objects: %d' % (len(units), len(objects)))

    items = {i: s for i, s in gen.item_sources(want_items).items() if i not in have_items}
    print('new items: %d' % len(items))

    # names -----------------------------------------------------------------
    creature_names = {int(r[0]): r[1] for r in
                      world.rows("SELECT entry, name FROM creature_template")}
    object_names = {int(r[0]): r[1] for r in
                    world.rows("SELECT entry, name FROM gameobject_template")}
    item_names = {int(r[0]): r[1] for r in
                  world.rows("SELECT entry, name FROM item_template")}
    quest_names = {int(r[0]): r[1] for r in
                   world.rows("SELECT ID, LogTitle FROM quest_template")}
    levels = {int(r[0]): (num(r[1]), num(r[2])) for r in
              world.rows("SELECT entry, minlevel, maxlevel FROM creature_template")}

    def level_text(entry):
        lo, hi = levels.get(entry, (0, 0))
        if not lo and not hi:
            return None
        return str(lo) if lo == hi else '%d-%d' % (lo, hi)

    # Zone names are overridden, not merely filled in. Blizzard reused old area
    # ids for Northrend - 3537 was "REUSE", 495 was "DELETE ME", 65 was
    # "***On Map Dungeon***" - and pfQuest still carries those dead names. The
    # addon finds the current zone by looking its name up in this table, so a
    # stale name means no nodes at all. The DBC is what the client itself
    # answers GetRealZoneText with, so it wins for every zone that has a map.
    zones = {area_id: area_names[area_id] for area_id in maps if area_names.get(area_id)}
    stale = sum(1 for z in zones if z in have_zones)
    minimap = {area_id: (l - r, t - b)
               for area_id, (m, l, r, t, b, _s) in maps.items() if area_id not in have_minimap}
    print('zone names: %d written (%d of them replacing an older entry), '
          'new minimap sizes: %d' % (len(zones), stale, len(minimap)))

    if args.dry_run:
        print('\nsample of what would be written:')
        for qid in sorted(quests)[:4]:
            e = quests[qid]
            starts = ','.join('%s:%s' % (k, sorted(v)) for k, v in (e.get('start') or {}).items())
            objs = ','.join('%s:%s' % (k, sorted(v)) for k, v in (e.get('obj') or {}).items())
            print('  quest %-6d lvl %-3s %-42s start %s  obj %s'
                  % (qid, e.get('lvl'), quest_names.get(qid, '?')[:42], starts or '-', objs or '-'))
        for uid in sorted(units)[:4]:
            coords = units[uid][:2]
            where = ' '.join('%.1f/%.1f in %s' % (c[0], c[1], area_names.get(c[2], c[2]))
                             for c in coords)
            print('  unit  %-6d %-32s %s' % (uid, creature_names.get(uid, '?')[:32], where))
        print('  new zones: %s' % ', '.join(sorted(zones.values()))[:300])
        print('\n--dry-run: nothing written')
        return



    # writing ---------------------------------------------------------------
    db = os.path.join(args.addon, 'db')
    loc = os.path.join(db, 'enUS')
    os.makedirs(loc, exist_ok=True)

    written = []

    def emit(path, assignment, entries):
        n = write_table(path, assignment, entries, HEADER)
        written.append((os.path.relpath(path, args.addon), n))

    emit(os.path.join(db, 'units-wotlk.lua'), 'pfDB["units"]["data-wotlk"]',
         [(u, render_unit(c, level_text(u))) for u, c in sorted(units.items())])
    emit(os.path.join(db, 'objects-wotlk.lua'), 'pfDB["objects"]["data-wotlk"]',
         [(o, render_object(c)) for o, c in sorted(objects.items())])
    emit(os.path.join(db, 'quests-wotlk.lua'), 'pfDB["quests"]["data-wotlk"]',
         [(q, render_quest(e)) for q, e in sorted(quests.items())])
    emit(os.path.join(db, 'items-wotlk.lua'), 'pfDB["items"]["data-wotlk"]',
         [(i, render_item(s)) for i, s in sorted(items.items())])
    emit(os.path.join(db, 'minimap-wotlk.lua'), 'pfDB["minimap-wotlk"]',
         [(z, '{%s,%s}' % (fmt(w), fmt(h))) for z, (w, h) in sorted(minimap.items())])

    emit(os.path.join(loc, 'units-wotlk.lua'), 'pfDB["units"]["enUS-wotlk"]',
         [(u, lua_string(creature_names.get(u, '?'))) for u in sorted(units)])
    emit(os.path.join(loc, 'objects-wotlk.lua'), 'pfDB["objects"]["enUS-wotlk"]',
         [(o, lua_string(object_names.get(o, '?'))) for o in sorted(objects)])
    emit(os.path.join(loc, 'items-wotlk.lua'), 'pfDB["items"]["enUS-wotlk"]',
         [(i, lua_string(item_names.get(i, '?'))) for i in sorted(items)])
    emit(os.path.join(loc, 'quests-wotlk.lua'), 'pfDB["quests"]["enUS-wotlk"]',
         [(q, '{%s}' % lua_string(quest_names.get(q, '?'))) for q in sorted(quests)])
    emit(os.path.join(loc, 'zones-wotlk.lua'), 'pfDB["zones"]["enUS-wotlk"]',
         [(z, lua_string(name)) for z, name in sorted(zones.items())])

    write_xml(args.addon)
    patch_toc(args.addon)

    print('\nwritten:')
    total = 0
    for name, count in written:
        size = os.path.getsize(os.path.join(args.addon, name))
        total += size
        print('  %-28s %7d entries  %8.1f KB' % (name, count, size / 1024))
    print('  %-28s %25.1f KB total' % ('', total / 1024))


DATA_XML = '''<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <!-- Generated by tools/pfquestgen/gen.py -->
  <Include file="..\\db\\items-wotlk.lua"/>
  <Include file="..\\db\\units-wotlk.lua"/>
  <Include file="..\\db\\objects-wotlk.lua"/>
  <Include file="..\\db\\quests-wotlk.lua"/>
  <Include file="..\\db\\minimap-wotlk.lua"/>
</Ui>
'''

LOCALE_XML = '''<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <!-- Generated by tools/pfquestgen/gen.py -->
  <Include file="..\\db\\enUS\\items-wotlk.lua"/>
  <Include file="..\\db\\enUS\\units-wotlk.lua"/>
  <Include file="..\\db\\enUS\\objects-wotlk.lua"/>
  <Include file="..\\db\\enUS\\quests-wotlk.lua"/>
  <Include file="..\\db\\enUS\\zones-wotlk.lua"/>
</Ui>
'''


def write_xml(addon):
    init = os.path.join(addon, 'init')
    open(os.path.join(init, 'data-wotlk.xml'), 'w').write(DATA_XML)
    open(os.path.join(init, 'enUS-wotlk.xml'), 'w').write(LOCALE_XML)


def patch_toc(addon):
    """Load the new layer last, so nothing reloaded after it wins.

    pfQuest's own .toc lists enUS.xml and enUS-tbc.xml twice. Inserting after
    the first copy would leave the second re-assigning the tables this layer
    is meant to sit on top of, so the new lines go after the LAST of each.
    """
    name = os.path.basename(addon.rstrip('/'))
    path = os.path.join(addon, name + '.toc')
    lines = open(path, encoding='utf-8').read().splitlines()
    lines = [l for l in lines if 'wotlk.xml' not in l.lower()]

    def insert_after_last(suffix, addition):
        last = None
        for i, line in enumerate(lines):
            if line.strip().lower().endswith(suffix):
                last = i
        if last is not None:
            lines.insert(last + 1, addition)

    insert_after_last('enus-tbc.xml', 'init\\enUS-wotlk.xml')
    insert_after_last('data-tbc.xml', 'init\\data-wotlk.xml')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
