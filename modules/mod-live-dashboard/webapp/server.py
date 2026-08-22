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
import json
import mimetypes
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DIST_DIR = Path(__file__).resolve().parent / "dist"

CLASS_NAMES = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    6: "Death Knight", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}

RACE_NAMES = {
    1: "Human", 2: "Orc", 3: "Dwarf", 4: "Night Elf", 5: "Undead",
    6: "Tauren", 7: "Gnome", 8: "Troll", 10: "Blood Elf", 11: "Draenei",
}


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
        rows = [line.split("\t") for line in proc.stdout.splitlines() if line]
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


def resolve_static_file(url_path: str) -> Path | None:
    """Maps a request path to a file under DIST_DIR, defaulting to index.html
    for `/` and refusing to escape DIST_DIR."""
    rel = url_path.lstrip("/") or "index.html"
    candidate = (DIST_DIR / rel).resolve()
    if DIST_DIR.resolve() not in candidate.parents and candidate != DIST_DIR.resolve():
        return None
    return candidate if candidate.is_file() else None


def make_handler(db: DB):
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

        def do_GET(self):
            try:
                if self.path == "/api/positions":
                    self._json(db.positions())
                elif self.path == "/api/stats":
                    self._json(db.stats())
                else:
                    self._static()
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))

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
    server = ThreadingHTTPServer((args.host, args.port), make_handler(db))
    print(f"Live dashboard: http://{args.host}:{args.port}  (DB config: {conf_path})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
