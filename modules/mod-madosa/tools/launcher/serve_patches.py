#!/usr/bin/env python3
"""Publish the client patches for the launcher to fetch.

    python3 serve_patches.py --add ../worldforged/out/patch-enus-z.mpq:Data/enUS
    python3 serve_patches.py                      # rebuild the manifest and serve
    python3 serve_patches.py --host 0.0.0.0       # ... reachable from the network

Everything under `public/` is served as-is, and `manifest.json` is generated from
whatever is in there: a path relative to the game folder, a size and a SHA-256
per file. The launcher compares those hashes against the player's copy and pulls
down only what differs.

Paths in the manifest are written the way a stock Windows install spells them
(`Data/enUS/...`). The launcher matches them case-insensitively against what the
player actually has, because a WoW folder copied around Linux, Wine and Windows
ends up with every spelling of `data`, `Data`, `enus` and `enUS` there is.

There is no built-in patch download in 3.3.5a - the game protocol cannot carry
files - so this is a plain web server plus a launcher that runs before the game,
which is how Ascension's own launcher does it too.
"""

import argparse
import hashlib
import http.server
import json
import shutil
import socketserver
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PUBLIC = HERE / "public"
MANIFEST = PUBLIC / "manifest.json"

# Where a file belongs inside the game folder, when --add does not say.
DEFAULT_DESTINATION = "Data/enUS"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_manifest(realm_name, realmlist):
    files = []
    for path in sorted(PUBLIC.rglob("*")):
        if not path.is_file() or path.name == "manifest.json":
            continue

        relative = path.relative_to(PUBLIC)
        files.append({
            # The directory layout under public/ *is* the layout in the game
            # folder, so a file at public/Data/enUS/x.mpq lands in Data/enUS/x.mpq.
            "path": relative.as_posix(),
            "size": path.stat().st_size,
            "sha256": sha256(path),
        })

    manifest = {
        "name": realm_name,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "files": files,
    }
    if realmlist:
        manifest["realmlist"] = realmlist

    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    total = sum(f["size"] for f in files)
    print(f"manifest: {len(files)} file(s), {total / 1024 / 1024:.1f} MB")
    for f in files:
        print(f"  {f['path']}  ({f['size'] / 1024 / 1024:.2f} MB)")
    return manifest


def add(spec):
    """--add <file>[:<destination folder inside the game directory>]"""
    source, _, destination = spec.partition(":")
    destination = destination or DEFAULT_DESTINATION

    source = Path(source).expanduser().resolve()
    if not source.is_file():
        raise SystemExit(f"not a file: {source}")

    target = PUBLIC / destination / source.name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(source, target)
    print(f"added {source.name} -> {target.relative_to(PUBLIC).as_posix()}")


def serve(host, port):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(*a, directory=str(PUBLIC), **kw)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((host, port), handler) as httpd:
        shown = host if host != "0.0.0.0" else "<this machine's address>"
        print(f"serving {PUBLIC} on http://{shown}:{port}")
        print(f"point the launcher's server_url at http://{shown}:{port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--add", action="append", metavar="FILE[:DEST]", default=[],
                    help=f"copy a patch into public/ (default destination {DEFAULT_DESTINATION})")
    ap.add_argument("--name", default="Madosa Realm", help="realm name shown in the launcher")
    ap.add_argument("--realmlist", default="", help="realmlist line the launcher writes for the player")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8788)
    ap.add_argument("--no-serve", action="store_true", help="only rebuild the manifest")
    args = ap.parse_args()

    PUBLIC.mkdir(exist_ok=True)
    for spec in args.add:
        add(spec)

    manifest = build_manifest(args.name, args.realmlist)
    if not manifest["files"]:
        print("nothing in public/ yet - add a patch with --add", file=sys.stderr)

    if not args.no_serve:
        serve(args.host, args.port)


if __name__ == "__main__":
    main()
