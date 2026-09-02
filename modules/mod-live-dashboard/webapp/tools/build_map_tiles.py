#!/usr/bin/env python3
"""Builds the dashboard's map tile pyramid from the client's own minimap.

The client ships one 256x256 BLP per ADT tile (textures/minimap, resolved
through md5translate.trs). This stitches them into a web-map pyramid - the
same scheme Google Maps uses - so the dashboard can zoom from a whole
continent down to a single tile at full minimap resolution without ever
loading more than the screenful it shows.

Zoom `maxZoom` is native: one 256 px web tile per ADT tile. Each level below
halves both axes, down to level 0 where the whole continent fits one tile.
Web tile (z, x, y) covers the native pixels [x * 256 * 2^(maxZoom - z), ...) of
the continent image, whose origin is the north-west-most existing ADT tile -
the same origin `MAP_TILES` in the frontend uses to place a dot.

Output goes to webapp/tiles/<mapId>/<z>/<x>/<y>.webp plus tiles/index.json
describing each continent's extent, and is gitignored: it is ~100 MB, built
in a minute from the client the server is already paired with.

Usage: build_map_tiles.py <client dir> [--out <dir>] [--quality 75]
"""

import argparse
import collections
import io
import json
import math
import os
import re
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "mod-madosa" / "tools" / "clientpatch"))
from mpq import MPQ  # noqa: E402  (mod-madosa's reader; shipped in this repo)

# Minimap directory name -> map id, in the same order the frontend tabs use.
CONTINENTS = {"Azeroth": 0, "Kalimdor": 1, "Expansion01": 530, "Northrend": 571}

# Later archives override earlier ones in the client, so search them first.
ARCHIVES = ["patch-3.mpq", "patch-2.mpq", "patch.mpq", "lichking.mpq", "expansion.mpq", "common-2.mpq", "common.mpq"]

TILE = 256


def open_archives(data_dir: Path):
    archives = []
    for name in ARCHIVES:
        path = data_dir / name
        if path.is_file():
            archives.append((name, MPQ(str(path))))
    if not archives:
        raise SystemExit(f"no MPQ archives found in {data_dir}")
    return archives


def read_any(archives, path: str):
    for _, archive in archives:
        try:
            data = archive.read_file(path)
        except Exception:
            continue
        if data:
            return data
    return None


def load_translate(archives):
    """dir -> {(col, row): hashed file name}"""
    raw = read_any(archives, "textures\\minimap\\md5translate.trs")
    if not raw:
        raise SystemExit("md5translate.trs not found in any archive")

    tiles = collections.defaultdict(dict)
    for line in raw.decode("latin1").splitlines():
        m = re.match(r"([^\\]+)\\map(\d+)_(\d+)\.blp\t(\S+)", line)
        if m:
            tiles[m.group(1)][(int(m.group(2)), int(m.group(3)))] = m.group(4)
    return tiles


def build_continent(name, map_id, tiles, archives, out: Path, quality: int):
    cols_present = [c for c, _ in tiles]
    rows_present = [r for _, r in tiles]
    col_min, col_max = min(cols_present), max(cols_present)
    row_min, row_max = min(rows_present), max(rows_present)
    cols = col_max - col_min + 1
    rows = row_max - row_min + 1
    max_zoom = max(1, math.ceil(math.log2(max(cols, rows))))

    print(f"{name} (map {map_id}): {len(tiles)} tiles, cols {col_min}..{col_max}, rows {row_min}..{row_max}, "
          f"{cols}x{rows}, maxZoom {max_zoom}")

    # Native level straight from the BLPs.
    native = {}
    for (col, row), hashed in tiles.items():
        blob = read_any(archives, "textures\\minimap\\" + hashed)
        if not blob:
            continue
        try:
            img = Image.open(io.BytesIO(blob)).convert("RGB")
        except Exception as e:  # a handful of tiles in every client are odd
            print(f"  skip {name} {col}_{row}: {e}")
            continue
        if img.size != (TILE, TILE):
            img = img.resize((TILE, TILE), Image.LANCZOS)
        native[(col - col_min, row - row_min)] = img

    level = native
    for z in range(max_zoom, -1, -1):
        zdir = out / str(map_id) / str(z)
        for (x, y), img in level.items():
            path = zdir / str(x) / f"{y}.webp"
            path.parent.mkdir(parents=True, exist_ok=True)
            img.save(path, "WEBP", quality=quality, method=4)

        if z == 0:
            break

        # Next level down: each 2x2 block of this level becomes one tile.
        # Missing quadrants (ocean) stay black, which is what the minimap
        # itself shows there.
        parent = {}
        for (x, y), img in level.items():
            key = (x // 2, y // 2)
            if key not in parent:
                parent[key] = Image.new("RGB", (TILE * 2, TILE * 2))
            parent[key].paste(img, ((x % 2) * TILE, (y % 2) * TILE))
        level = {key: img.resize((TILE, TILE), Image.LANCZOS) for key, img in parent.items()}

    return {
        "colMin": col_min, "cols": cols, "rowMin": row_min, "rows": rows,
        "maxZoom": max_zoom, "tiles": len(native),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("client", type=Path, help="WoW 3.3.5a client directory (the one holding data/)")
    parser.add_argument("--out", type=Path, default=HERE.parent / "tiles")
    parser.add_argument("--quality", type=int, default=75)
    args = parser.parse_args()

    data_dir = args.client / "data"
    if not data_dir.is_dir():
        data_dir = args.client / "Data"
    archives = open_archives(data_dir)
    translate = load_translate(archives)

    index = {}
    for name, map_id in CONTINENTS.items():
        if name not in translate:
            print(f"{name}: no minimap tiles listed, skipped")
            continue
        index[str(map_id)] = build_continent(name, map_id, translate[name], archives, args.out, args.quality)

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "index.json").write_text(json.dumps(index, indent=2))
    total = sum(f.stat().st_size for f in args.out.rglob("*.webp"))
    print(f"done: {args.out}, {total / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
