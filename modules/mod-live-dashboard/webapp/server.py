#!/usr/bin/env python3
"""Standalone live dashboard backend for mod-live-dashboard.

Reads DB connection info straight out of the AzerothCore install's own
worldserver.conf (no separate credentials file to keep in sync), polls the
`live_player_positions` table that the C++ module keeps fresh, and exposes it
as JSON under /api/*. Talks to MySQL via the `mysql` CLI (no extra pip
packages required).

The actual UI is the Vite/React app in frontend/. Two ways to run this:

  - Dev:  `npm run dev` in frontend/ (proxies /api to this server on :8787),
          then run this script separately and open the Vite dev URL.
  - Prod: `npm run build` in frontend/ (outputs to webapp/dist/), then just
          run this script - it serves the built app AND the API on :8787.
"""

import argparse
import base64
import os
import secrets
import json
import mimetypes
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
from pathlib import Path

DIST_DIR = Path(__file__).resolve().parent / "dist"

# The map tile pyramid, built from the client by tools/build_map_tiles.py.
# Served from its own directory rather than copied into dist/ by the frontend
# build: it is ~100 MB and regenerated locally, not shipped.
TILES_DIR = Path(__file__).resolve().parent / "tiles"

# Item icons, built from the client by tools/build_item_icons.py: one webp per
# icon name under icons/, and index.json mapping item display id -> name. Read
# once at startup; an install without it simply gets no icons on the sheet.
ICONS_DIR = Path(__file__).resolve().parent / "icons"


def load_icon_index() -> dict:
    try:
        return json.loads((ICONS_DIR / "index.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


ICON_BY_DISPLAY_ID = load_icon_index()


def load_spell_text() -> dict:
    try:
        return json.loads((ICONS_DIR / "spells.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


SPELL_TEXT = load_spell_text()

# item_template.stat_type -> what the tooltip says. The first group are the
# white "+N Stat" lines; everything else the game phrases as a green "Equip:"
# line, and so does this.
STAT_NAMES = {
    0: "Mana", 1: "Health", 3: "Agility", 4: "Strength", 5: "Intellect", 6: "Spirit", 7: "Stamina",
}
RATING_TEXT = {
    12: "Increases defense rating by {}.", 13: "Increases your dodge rating by {}.",
    14: "Increases your parry rating by {}.", 15: "Increases your shield block rating by {}.",
    16: "Improves melee hit rating by {}.", 17: "Improves ranged hit rating by {}.",
    18: "Improves spell hit rating by {}.", 19: "Improves melee critical strike rating by {}.",
    20: "Improves ranged critical strike rating by {}.", 21: "Improves spell critical strike rating by {}.",
    28: "Improves melee haste rating by {}.", 29: "Improves ranged haste rating by {}.",
    30: "Improves spell haste rating by {}.", 31: "Improves hit rating by {}.",
    32: "Improves critical strike rating by {}.", 35: "Improves your resilience rating by {}.",
    36: "Improves haste rating by {}.", 37: "Increases your expertise rating by {}.",
    38: "Increases attack power by {}.", 39: "Increases ranged attack power by {}.",
    40: "Increases attack power by {} in Cat, Bear, Dire Bear, and Moonkin forms only.",
    41: "Increases healing done by spells by {}.", 42: "Increases damage done by spells by {}.",
    43: "Restores {} mana per 5 sec.", 44: "Increases your armor penetration rating by {}.",
    45: "Increases spell power by {}.", 46: "Restores {} health per 5 sec.",
    47: "Increases your spell penetration by {}.", 48: "Increases the block value of your shield by {}.",
}
BINDING = {1: "Binds when picked up", 2: "Binds when equipped", 3: "Binds when used", 4: "Quest Item"}
INVENTORY_TYPE = {
    1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist", 7: "Legs", 8: "Feet", 9: "Wrist",
    10: "Hands", 11: "Finger", 12: "Trinket", 13: "One-Hand", 14: "Off Hand", 15: "Ranged", 16: "Back",
    17: "Two-Hand", 18: "Bag", 19: "Tabard", 20: "Chest", 21: "Main Hand", 22: "One-Hand", 23: "Held In Off-hand",
    24: "Ammo", 25: "Thrown", 26: "Ranged", 28: "Relic",
}
ARMOR_SUBCLASS = {1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate", 6: "Shield", 7: "Libram", 8: "Idol", 9: "Totem", 10: "Sigil"}
WEAPON_SUBCLASS = {
    0: "Axe", 1: "Axe", 2: "Bow", 3: "Gun", 4: "Mace", 5: "Mace", 6: "Polearm", 7: "Sword", 8: "Sword",
    10: "Staff", 13: "Fist Weapon", 15: "Dagger", 16: "Thrown", 18: "Crossbow", 19: "Wand", 20: "Fishing Pole",
}
SPELL_TRIGGER_EQUIP = 1
SPELL_TRIGGER_USE = 0


def spell_line(spell_id: int) -> str:
    """The tooltip text of an equip/use spell, with its values filled in.
    A description whose placeholders are beyond $s1-$s3 (durations, chained
    spells) is dropped rather than shown half-resolved."""
    entry = SPELL_TEXT.get(str(spell_id))
    if not entry:
        return ""
    text, s1, s2, s3 = entry
    text = text.replace("$s1", str(abs(s1))).replace("$s2", str(abs(s2))).replace("$s3", str(abs(s3)))
    if "$" in text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def item_tooltip(g: list) -> dict:
    """Everything the game's tooltip shows for an item, from item_template."""
    (cls, subclass, inv_type, bonding, req_level, armor, dmg_min, dmg_max, delay,
     max_durability, sell_price, description, durability) = (
        int(g[7]), int(g[8]), int(g[9]), int(g[10]), int(g[11]), int(g[12]), float(g[13]), float(g[14]),
        int(g[15]), int(g[16]), int(g[17]), g[18], int(g[19]))
    stats = [(int(g[20 + 2 * k]), int(g[21 + 2 * k])) for k in range(10)]
    spells = [(int(g[40 + 2 * k]), int(g[41 + 2 * k])) for k in range(3)]

    tip = {
        "binding": BINDING.get(bonding, ""),
        "slot": INVENTORY_TYPE.get(inv_type, ""),
        "type": "",
        "armor": armor,
        "damage": None,
        "stats": [],
        "equip": [],
        "use": [],
        "durability": [durability, max_durability] if max_durability else None,
        "reqLevel": req_level,
        "sell": sell_price,
        "flavor": description,
    }
    if cls == 4:
        tip["type"] = ARMOR_SUBCLASS.get(subclass, "")
    elif cls == 2:
        tip["type"] = WEAPON_SUBCLASS.get(subclass, "")
        if delay:
            speed = delay / 1000.0
            tip["damage"] = {
                "min": int(dmg_min), "max": int(dmg_max), "speed": round(speed, 2),
                "dps": round((dmg_min + dmg_max) / 2.0 / speed, 1),
            }
    for stat_type, value in stats:
        if not value:
            continue
        if stat_type in STAT_NAMES:
            tip["stats"].append({"name": STAT_NAMES[stat_type], "value": value})
        elif stat_type in RATING_TEXT:
            tip["equip"].append(RATING_TEXT[stat_type].format(value))
    for spell_id, trigger in spells:
        if not spell_id:
            continue
        line = spell_line(spell_id)
        if not line:
            continue
        if trigger == SPELL_TRIGGER_EQUIP:
            tip["equip"].append(line)
        elif trigger == SPELL_TRIGGER_USE:
            tip["use"].append(line)
    return tip

CLASS_NAMES = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    6: "Death Knight", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}

RACE_NAMES = {
    1: "Human", 2: "Orc", 3: "Dwarf", 4: "Night Elf", 5: "Undead",
    6: "Tauren", 7: "Gnome", 8: "Troll", 10: "Blood Elf", 11: "Draenei",
}

# The primary and secondary professions, by SkillLine id. Hard-coded rather
# than read from SkillLine.dbc because this server has no DBC reader and the
# list has not changed since 3.3.5 shipped.
PROFESSIONS = {
    171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
    182: "Herbalism", 773: "Inscription", 755: "Jewelcrafting", 165: "Leatherworking",
    186: "Mining", 393: "Skinning", 197: "Tailoring",
    129: "First Aid", 185: "Cooking", 356: "Fishing",
}

# Equipment slots that say nothing about a character's gear level.
COSMETIC_SLOTS = {3, 18}   # shirt, tabard


TOKEN_FILE = Path(__file__).resolve().parent / ".admin-token"


def load_or_create_token() -> str:
    """The shared secret the admin endpoints require.

    Generated on first run and kept in a file next to this script, mode 0600.
    Everything read-only stays open the way it always was - it is only the
    endpoints that can change the running server that are gated, because those
    run with console rights on the other side.
    """
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()
        if token:
            return token

    token = secrets.token_urlsafe(24)
    TOKEN_FILE.write_text(token, encoding="utf-8")
    os.chmod(TOKEN_FILE, 0o600)
    return token


def find_default_conf() -> Path:
    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "env" / "dist" / "etc" / "worldserver.conf"


def parse_db_info(conf_path: Path, key: str) -> dict:
    text = conf_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    if not m:
        raise SystemExit(f"Could not find {key} in {conf_path}")
    host, port, user, password, database = m.group(1).split(";")
    return {"host": host, "port": port, "user": user, "password": password, "database": database}


class DB:
    def __init__(self, conf_path: Path):
        self.characters = parse_db_info(conf_path, "CharacterDatabaseInfo")
        self.world = parse_db_info(conf_path, "WorldDatabaseInfo")

    def query(self, sql: str, info: dict) -> list:
        proc = subprocess.run(
            [
                "mysql",
                f"-h{info['host']}",
                f"-P{info['port']}",
                f"-u{info['user']}",
                "-N", "-B",
                info["database"],
            ],
            input=sql,
            env={"MYSQL_PWD": info["password"]},
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip())
        # Split on newlines only. str.splitlines() also breaks on \r, and
        # console output captured from the game process carries carriage
        # returns inside a single field - which tore one row into several and
        # left the caller indexing past the end of it.
        rows = [line.split("\t") for line in proc.stdout.split("\n") if line]
        return rows

    def positions(self) -> list:
        rows = self.query(
            "SELECT guid, name, is_bot, level, class, race, map_id, zone_id, area_id, "
            "area_name, pos_x, pos_y, pct_x, pct_y, hp_pct, guild_name FROM live_player_positions",
            self.characters,
        )
        out = []
        for r in rows:
            (guid, name, is_bot, level, cls, race, map_id, zone_id, area_id, area_name,
             pos_x, pos_y, pct_x, pct_y, hp_pct, guild_name) = r
            out.append({
                "guid": int(guid),
                "name": name,
                "isBot": is_bot == "1",
                "level": int(level),
                "class": CLASS_NAMES.get(int(cls), f"Class {cls}"),
                "race": RACE_NAMES.get(int(race), f"Race {race}"),
                "mapId": int(map_id),
                "zoneId": int(zone_id),
                "areaId": int(area_id),
                "areaName": area_name or f"Area {area_id}",
                "posX": float(pos_x),
                "posY": float(pos_y),
                "pctX": float(pct_x),
                "pctY": float(pct_y),
                "hpPct": int(hp_pct),
                "guild": guild_name,
            })
        return out

    def character(self, guid: int) -> dict | None:
        """One character's sheet, the way an armory would show it: who they
        are, what they wear, what they can make. Read from the tables the
        game itself persists, so it is a few seconds behind the world at most
        and works for someone who is offline too."""
        guid = int(guid)
        rows = self.query(
            "SELECT c.name, c.race, c.class, c.gender, c.level, c.money, c.totaltime, c.leveltime, "
            "c.online, c.totalKills, c.totalHonorPoints, c.arenaPoints, c.logout_time, "
            "IFNULL(g.name, ''), c.skin, c.face, c.hairStyle, c.hairColor, c.facialStyle FROM characters c "
            "LEFT JOIN guild_member gm ON gm.guid = c.guid LEFT JOIN guild g ON g.guildid = gm.guildid "
            f"WHERE c.guid = {guid}",
            self.characters,
        )
        if not rows or len(rows[0]) < 19:
            return None
        r = rows[0]

        gear = self.query(
            "SELECT ci.slot, ii.itemEntry, it.name, it.Quality, it.ItemLevel, it.displayid, it.InventoryType, "
            "it.class, it.subclass, it.InventoryType, it.bonding, it.RequiredLevel, it.armor, "
            "it.dmg_min1, it.dmg_max1, it.delay, it.MaxDurability, it.SellPrice, it.description, ii.durability, "
            + ", ".join(f"it.stat_type{k}, it.stat_value{k}" for k in range(1, 11)) + ", "
            + ", ".join(f"it.spellid_{k}, it.spelltrigger_{k}" for k in range(1, 4)) + " "
            "FROM character_inventory ci "
            "JOIN item_instance ii ON ii.guid = ci.item "
            f"JOIN {self.world['database']}.item_template it ON it.entry = ii.itemEntry "
            f"WHERE ci.guid = {guid} AND ci.bag = 0 AND ci.slot < 19 ORDER BY ci.slot",
            self.characters,
        )
        equipment = [
            {
                "slot": int(g[0]), "entry": int(g[1]), "name": g[2], "quality": int(g[3]), "ilvl": int(g[4]),
                "displayId": int(g[5]), "icon": ICON_BY_DISPLAY_ID.get(g[5], ""),
                "tooltip": item_tooltip(g),
            }
            for g in gear if len(g) >= 46
        ]
        rated = [e["ilvl"] for e in equipment if e["slot"] not in COSMETIC_SLOTS]
        avg_ilvl = round(sum(rated) / len(rated)) if rated else 0

        skills = self.query(
            f"SELECT skill, value, max FROM character_skills WHERE guid = {guid} "
            f"AND skill IN ({','.join(str(k) for k in PROFESSIONS)}) ORDER BY value DESC",
            self.characters,
        )
        professions = [
            {"name": PROFESSIONS[int(sk[0])], "value": int(sk[1]), "max": int(sk[2])}
            for sk in skills if len(sk) >= 3 and int(sk[0]) in PROFESSIONS
        ]

        live = self.query(
            f"SELECT is_bot FROM live_player_positions WHERE guid = {guid}",
            self.characters,
        )

        cls = int(r[2])
        race = int(r[1])
        return {
            "guid": guid,
            "name": r[0],
            "race": RACE_NAMES.get(race, f"Race {race}"),
            "class": CLASS_NAMES.get(cls, f"Class {cls}"),
            "raceId": race,
            "classId": cls,
            "gender": "female" if r[3] == "1" else "male",
            "appearance": {
                "skin": int(r[14]), "face": int(r[15]), "hairStyle": int(r[16]),
                "hairColor": int(r[17]), "facialStyle": int(r[18]),
            },
            "level": int(r[4]),
            "money": int(r[5]),
            "totaltime": int(r[6]),
            "leveltime": int(r[7]),
            "online": r[8] == "1",
            "totalKills": int(r[9]),
            "totalHonorPoints": int(r[10]),
            "arenaPoints": int(r[11]),
            "logoutTime": int(r[12]),
            "guild": r[13],
            "isBot": bool(live and live[0] and live[0][0] == "1"),
            "avgItemLevel": avg_ilvl,
            "equipment": equipment,
            "professions": professions,
        }

    def chronicle(self, limit: int = 200, kind: str = "") -> list:
        """The recent past, newest first."""
        limit = max(1, min(int(limit), 500))
        where = ""
        if kind:
            safe = "".join(c for c in kind if c.isalnum() or c == "_")[:32]
            if safe:
                where = f"WHERE kind = '{safe}'"
        rows = self.query(
            "SELECT id, at, kind, actor, actor_bot, actor_class, actor_level, target, "
            f"target_bot, zone, map, value, IFNULL(detail,'') FROM live_chronicle {where} "
            f"ORDER BY id DESC LIMIT {limit}",
            self.characters,
        )
        return _chronicle_rows(rows)

    def chronicle_summary(self) -> dict:
        """The numbers the chronicle header shows: how busy the realm has been,
        and who has been busiest."""
        counts = self.query(
            "SELECT kind, COUNT(*), SUM(at > UNIX_TIMESTAMP() - 86400) "
            "FROM live_chronicle GROUP BY kind ORDER BY 2 DESC",
            self.characters,
        )
        killers = self.query(
            "SELECT actor, actor_bot, COUNT(*) FROM live_chronicle "
            "WHERE kind = 'pvp_kill' GROUP BY actor, actor_bot ORDER BY 3 DESC LIMIT 8",
            self.characters,
        )
        finders = self.query(
            "SELECT actor, actor_bot, COUNT(*) FROM live_chronicle "
            "WHERE kind = 'worldforged' GROUP BY actor, actor_bot ORDER BY 3 DESC LIMIT 8",
            self.characters,
        )
        span = self.query(
            "SELECT IFNULL(MIN(at),0), IFNULL(MAX(at),0), COUNT(*) FROM live_chronicle",
            self.characters,
        )
        return {
            "kinds": [
                {"kind": k, "total": int(t or 0), "today": int(d or 0)}
                for k, t, d in (r for r in counts if len(r) >= 3)
            ],
            "top_killers": [
                {"name": n, "bot": int(b or 0), "count": int(c or 0)}
                for n, b, c in (r for r in killers if len(r) >= 3)
            ],
            "top_finders": [
                {"name": n, "bot": int(b or 0), "count": int(c or 0)}
                for n, b, c in (r for r in finders if len(r) >= 3)
            ],
            "first": int(span[0][0]) if span else 0,
            "last": int(span[0][1]) if span else 0,
            "total": int(span[0][2]) if span else 0,
        }

    def queue_command(self, command: str) -> int:
        """Hands a command to the game process and returns its queue id.

        Nothing is executed here - the module picks the row up on its next tick.
        Quoting is the only sharp edge, and it is handled the same way the rest
        of this file handles it.
        """
        safe = command.replace("\\", "\\\\").replace("'", "\\'")[:500]

        # Both statements in one invocation on purpose: query() spawns a fresh
        # mysql process each time, and LAST_INSERT_ID() is per connection - ask
        # for it separately and the answer is always 0.
        rows = self.query(
            "INSERT INTO live_dashboard_commands (created_at, command) "
            f"VALUES (UNIX_TIMESTAMP(), '{safe}'); SELECT LAST_INSERT_ID();",
            self.characters,
        )
        return int(rows[-1][0]) if rows and rows[-1] else 0

    def command_result(self, cid: int) -> dict:
        """Command output is base64 on the wire.

        It is console output: multi-line, and carrying whatever carriage
        returns and tabs the formatting used. The tab-separated text the mysql
        CLI speaks cannot express that - a two-line answer arrives as two rows
        and the caller indexes past the end of the first. Base64 sidesteps the
        transport entirely rather than guessing at an escaping scheme.
        """
        rows = self.query(
            # MySQL's TO_BASE64 wraps at 76 characters, which would put the
            # value back across several lines - the exact problem base64 is
            # here to avoid.
            "SELECT id, status, REPLACE(REPLACE(TO_BASE64(IFNULL(output,'')), '\\n', ''), '\\r', ''), "
            "executed_at, command "
            f"FROM live_dashboard_commands WHERE id = {int(cid)}",
            self.characters,
        )
        if not rows or len(rows[0]) < 5:
            return {"id": int(cid), "status": "unknown", "output": "", "command": ""}

        r = rows[0]
        try:
            output = base64.b64decode(r[2]).decode("utf-8", "replace")
        except Exception:
            output = ""

        return {
            "id": int(r[0]),
            "status": r[1],
            "output": output,
            "executed_at": int(r[3] or 0),
            "command": r[4],
        }

    def command_history(self, limit: int = 30) -> list:
        rows = self.query(
            "SELECT id, created_at, command, status, executed_at "
            f"FROM live_dashboard_commands ORDER BY id DESC LIMIT {max(1, min(int(limit), 200))}",
            self.characters,
        )
        return [
            {"id": int(r[0]), "created_at": int(r[1]), "command": r[2],
             "status": r[3], "executed_at": int(r[4] or 0)}
            for r in rows if len(r) >= 5
        ]

    def stats(self) -> dict:
        counts = self.query(
            "SELECT is_bot, COUNT(*) FROM live_player_positions GROUP BY is_bot",
            self.characters,
        )
        players = bots = 0
        for is_bot, c in counts:
            if is_bot == "1":
                bots = int(c)
            else:
                players = int(c)

        guilds = self.query(
            "SELECT guild_name, COUNT(*) c FROM live_player_positions "
            "WHERE guild_name != '' GROUP BY guild_name ORDER BY c DESC LIMIT 5",
            self.characters,
        )

        ah_summary = self.query(
            "SELECT COUNT(*), COALESCE(SUM(buyoutprice), 0) FROM auctionhouse",
            self.characters,
        )
        ah_count, ah_total = (ah_summary[0] if ah_summary else ("0", "0"))

        top_auctions = self.query(
            "SELECT it.name, ah.buyoutprice FROM auctionhouse ah "
            "JOIN item_instance ii ON ii.guid = ah.itemguid "
            f"JOIN {self.world['database']}.item_template it ON it.entry = ii.itemEntry "
            "ORDER BY ah.buyoutprice DESC LIMIT 5",
            self.characters,
        )

        return {
            "playersOnline": players,
            "botsOnline": bots,
            "topGuilds": [{"name": g, "online": int(c)} for g, c in guilds],
            "auctionCount": int(ah_count),
            "auctionGoldTotal": int(ah_total) // 10000,
            "topAuctions": [{"item": name, "buyoutGold": int(price) // 10000} for name, price in top_auctions],
        }


CHRONICLE_COLUMNS = ("id", "at", "kind", "actor", "actor_bot", "actor_class",
                     "actor_level", "target", "target_bot", "zone", "map", "value", "detail")


def _chronicle_rows(rows: list) -> list:
    out = []
    for r in rows:
        if len(r) < len(CHRONICLE_COLUMNS):
            continue
        e = dict(zip(CHRONICLE_COLUMNS, r))
        for k in ("id", "at", "actor_bot", "actor_class", "actor_level",
                  "target_bot", "map", "value"):
            try:
                e[k] = int(e[k])
            except (TypeError, ValueError):
                e[k] = 0
        out.append(e)
    return out


def resolve_tile(url_path: str) -> Path | None:
    """/tiles/<map>/<z>/<x>/<y>.webp or /tiles/index.json, confined to TILES_DIR."""
    rel = url_path[len("/tiles/"):]
    if not rel or ".." in rel:
        return None
    candidate = (TILES_DIR / rel).resolve()
    if TILES_DIR.resolve() not in candidate.parents:
        return None
    return candidate if candidate.is_file() else None


def resolve_icon(url_path: str) -> Path | None:
    """/icons/<name>.webp, confined to ICONS_DIR."""
    name = url_path[len("/icons/"):]
    if not re.fullmatch(r"[a-z0-9_\-]+\.webp", name):
        return None
    candidate = ICONS_DIR / name
    return candidate if candidate.is_file() else None


def resolve_static_file(url_path: str) -> Path | None:
    """Maps a request path to a file under DIST_DIR, defaulting to index.html
    for `/` and refusing to escape DIST_DIR."""
    rel = url_path.lstrip("/") or "index.html"
    candidate = (DIST_DIR / rel).resolve()
    if DIST_DIR.resolve() not in candidate.parents and candidate != DIST_DIR.resolve():
        return None
    return candidate if candidate.is_file() else None


def make_handler(db: DB, token: str):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def _json(self, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _icon(self, url_path):
            path = resolve_icon(url_path)
            if path is None:
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            body = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/webp")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "public, max-age=604800")
            self.end_headers()
            self.wfile.write(body)

        def _tile(self, url_path):
            path = resolve_tile(url_path)
            if path is None:
                # Leaflet asks for every tile in view; the ocean has none, and
                # the layer's errorTileUrl paints those transparent.
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            body = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/webp" if path.suffix == ".webp" else "application/json")
            self.send_header("Content-Length", str(len(body)))
            # Tiles only change when the client does; a day is short enough to
            # pick up a rebuild and long enough to never fetch one twice on a
            # walk across a continent.
            self.send_header("Cache-Control", "public, max-age=86400")
            self.end_headers()
            self.wfile.write(body)

        def _static(self):
            path = resolve_static_file(self.path.split("?", 1)[0])
            if path is None:
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(
                    b"Not found. Did you run `npm run build` in webapp/frontend/?"
                )
                return
            content_type, _ = mimetypes.guess_type(str(path))
            body = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type or "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _deny(self, code, message):
            body = json.dumps({"error": message}).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authorised(self) -> bool:
            """Constant-time compare, and the header is the only accepted place
            for the token - a query string would end up in logs and history."""
            supplied = self.headers.get("X-Admin-Token", "")
            return secrets.compare_digest(supplied, token)

        def do_GET(self):
            try:
                path, _, raw_query = self.path.partition("?")
                query = parse_qs(raw_query)

                if path.startswith("/tiles/"):
                    self._tile(path)
                elif path.startswith("/icons/"):
                    self._icon(path)
                elif path == "/api/positions":
                    self._json(db.positions())
                elif path == "/api/stats":
                    self._json(db.stats())
                elif path == "/api/chronicle":
                    self._json(db.chronicle(
                        limit=int(query.get("limit", [200])[0] or 200),
                        kind=query.get("kind", [""])[0],
                    ))
                elif path == "/api/chronicle/summary":
                    self._json(db.chronicle_summary())
                elif path == "/api/character":
                    sheet = db.character(int(query.get("guid", [0])[0] or 0))
                    if sheet is None:
                        return self._deny(404, "no such character")
                    self._json(sheet)
                elif path == "/api/admin/result":
                    if not self._authorised():
                        return self._deny(403, "admin token required")
                    self._json(db.command_result(int(query.get("id", [0])[0] or 0)))
                elif path == "/api/admin/history":
                    if not self._authorised():
                        return self._deny(403, "admin token required")
                    self._json(db.command_history())
                else:
                    self._static()
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))

        def do_POST(self):
            try:
                path = self.path.split("?", 1)[0]
                if path != "/api/admin/command":
                    return self._deny(404, "not found")

                if not self._authorised():
                    return self._deny(403, "admin token required")

                length = int(self.headers.get("Content-Length") or 0)
                if length <= 0 or length > 4096:
                    return self._deny(400, "empty or oversized request")

                payload = json.loads(self.rfile.read(length).decode("utf-8"))
                command = str(payload.get("command", "")).strip()
                if not command:
                    return self._deny(400, "no command given")

                # A leading dot is how a GM types it and how every button here
                # is labelled; the console itself does not want one.
                self._json({"id": db.queue_command(command.lstrip("."))})
            except Exception as e:
                self._deny(500, str(e))

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--conf", type=Path, default=None, help="Path to worldserver.conf (default: auto-detect)")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host (default: localhost only)")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()

    conf_path = args.conf or find_default_conf()
    if not conf_path.is_file():
        raise SystemExit(f"Config not found: {conf_path} (pass --conf explicitly)")

    db = DB(conf_path)
    token = load_or_create_token()
    server = ThreadingHTTPServer((args.host, args.port), make_handler(db, token))
    print(f"Live dashboard: http://{args.host}:{args.port}  (DB config: {conf_path})")
    print(f"Admin token:    {token}")
    print(f"                (kept in {TOKEN_FILE}; delete that file to roll it)")
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        print("WARNING: bound beyond localhost. The admin console runs commands with")
        print("         console rights - only do this on a network you trust.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
