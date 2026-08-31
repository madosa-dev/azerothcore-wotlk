#!/usr/bin/env python3
"""Launcher for the realm: checks for client patches, fetches them, starts WoW.

A Windows program - which on Linux means running it through Wine, in the same
prefix as the game, so that starting Wow.exe from it works the way it always
does.

    python3 madosa_launcher.py              # window if one can be opened, else text
    python3 madosa_launcher.py --cli        # text, always
    python3 madosa_launcher.py --check      # update only, do not start the game

Give this file to a player together with nothing else. On first run it asks for
their WoW folder, remembers it in `madosa_launcher.json` beside itself, and from
then on every start compares their patches against the realm's manifest and
downloads only what changed.

Why a launcher at all: the 3.3.5a client has no patch download of its own and
the game protocol cannot carry files, so patches have to arrive before the game
starts. That is what Ascension's launcher does too.

Standard library only, so a frozen build needs nothing bundled beyond Python
itself. The window uses tkinter, which ships with Python on Windows; if it
cannot be opened at all the launcher runs the same routine on the terminal
rather than refusing to start, which is also how it stays testable on a Linux
box without `python3-tk`.

Where the game folder is spelled differently
--------------------------------------------
A WoW folder that has been copied between Windows, Wine and Linux ends up with
any mixture of `Data`/`data` and `enUS`/`enus`, and on a case-sensitive
filesystem writing the wrong one silently creates a second directory the client
never reads. Every manifest path is therefore resolved against the directories
that actually exist, one component at a time.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "madosa_launcher.json"

DEFAULT_SERVER_URL = "http://127.0.0.1:8788"
DOWNLOAD_CHUNK = 1 << 18
NETWORK_TIMEOUT = 30

GAME_MARKERS = ("wow.exe", "Wow.exe", "WoW.exe")


# --------------------------------------------------------------------------
# Configuration and the game folder
# --------------------------------------------------------------------------

def load_config():
    if CONFIG_PATH.is_file():
        try:
            return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {}


def save_config(config):
    CONFIG_PATH.write_text(json.dumps(config, indent=1) + "\n", encoding="utf-8")


def find_game_executable(game_dir):
    game_dir = Path(game_dir)
    for name in GAME_MARKERS:
        if (game_dir / name).is_file():
            return game_dir / name

    # Case-insensitive filesystems answer above; case-sensitive ones need a look.
    if game_dir.is_dir():
        for entry in game_dir.iterdir():
            if entry.is_file() and entry.name.lower() == "wow.exe":
                return entry
    return None


def resolve_existing_path(root, relative):
    """Map a manifest path onto the spelling this installation actually uses.

    `Data/enUS/patch-enus-z.mpq` has to land in `data/enus/` when that is what
    the player has, or the client never sees it. Components that do not exist yet
    keep the manifest's spelling.
    """
    current = Path(root)
    for part in Path(relative).parts:
        if (current / part).exists():
            current = current / part
            continue

        match = None
        if current.is_dir():
            lowered = part.lower()
            match = next((e.name for e in current.iterdir() if e.name.lower() == lowered), None)
        current = current / (match or part)
    return current


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def launch_command(config, executable):
    """How to start the game.

    This is a Windows program, so the normal answer is "run Wow.exe" - including
    under Wine, where the launcher and the game share a prefix and Wine starts it
    the same way it started the launcher. A configured `launch_command` overrides
    that for anyone who needs something else; `{exe}` in it stands for the
    executable's path.
    """
    if configured := config.get("launch_command"):
        return [str(executable) if part == "{exe}" else part for part in configured]

    return [str(executable)]


# --------------------------------------------------------------------------
# The update itself - no user interface in here, so both front ends share it
# --------------------------------------------------------------------------

class UpdateError(Exception):
    pass


def fetch_manifest(server_url):
    try:
        with urllib.request.urlopen(f"{server_url}/manifest.json", timeout=NETWORK_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise UpdateError(f"Could not reach {server_url}: {e.reason}") from e
    except ValueError as e:
        raise UpdateError(f"{server_url} did not answer with a manifest.") from e


def outdated_files(manifest, game_dir):
    """The manifest entries whose local copy is missing or different."""
    out = []
    for entry in manifest.get("files", []):
        target = resolve_existing_path(game_dir, entry["path"])
        if not target.is_file() or target.stat().st_size != entry["size"] \
                or sha256(target) != entry["sha256"]:
            out.append((entry, target))
    return out


def download(server_url, outdated, report):
    total = sum(entry["size"] for entry, _ in outdated)
    done = 0

    for entry, target in outdated:
        report(f"Downloading {Path(entry['path']).name}...", done * 100 / max(total, 1))
        target.parent.mkdir(parents=True, exist_ok=True)

        # Into a temporary file first: a half-written MPQ under the real name
        # would look complete on the next start and break the client instead.
        temporary = target.with_suffix(target.suffix + ".part")
        try:
            with urllib.request.urlopen(f"{server_url}/{entry['path']}", timeout=NETWORK_TIMEOUT) as response, \
                    open(temporary, "wb") as fh:
                while chunk := response.read(DOWNLOAD_CHUNK):
                    fh.write(chunk)
                    done += len(chunk)
                    report(None, min(99.0, done * 100 / max(total, 1)))
        except urllib.error.URLError as e:
            temporary.unlink(missing_ok=True)
            raise UpdateError(f"Download of {entry['path']} failed: {e.reason}") from e

        if sha256(temporary) != entry["sha256"]:
            temporary.unlink(missing_ok=True)
            raise UpdateError(f"{entry['path']} arrived damaged - try again.")

        os.replace(temporary, target)


def write_realmlist(manifest, game_dir):
    line = manifest.get("realmlist")
    if not line:
        return

    for name in ("realmlist.wtf", "Data/enUS/realmlist.wtf", "Data/enGB/realmlist.wtf"):
        path = resolve_existing_path(game_dir, name)
        if not path.parent.is_dir():
            continue
        try:
            if path.read_text(encoding="utf-8", errors="ignore").strip() == line.strip():
                continue
        except OSError:
            pass
        try:
            path.write_text(line.rstrip() + "\n", encoding="utf-8")
        except OSError:
            pass    # a read-only install is not a reason to refuse to play


def update(config, report):
    """Bring the client up to date. Returns the manifest."""
    server_url = config.get("server_url", DEFAULT_SERVER_URL)
    game_dir = Path(config["game_dir"])

    report("Checking for updates...", 0)
    manifest = fetch_manifest(server_url)

    pending = outdated_files(manifest, game_dir)
    if pending:
        download(server_url, pending, report)
    write_realmlist(manifest, game_dir)

    report("Up to date." if not pending else f"Updated {len(pending)} file(s).", 100)
    return manifest


# --------------------------------------------------------------------------
# Front ends
# --------------------------------------------------------------------------

def run_cli(config, start_game):
    last = [""]

    def report(status, percent):
        if status:
            last[0] = status
            print(f"\r{status:<48}", end="", flush=True)
        elif percent is not None:
            print(f"\r{last[0]:<38}{percent:5.1f}%", end="", flush=True)

    try:
        update(config, report)
        print()
    except UpdateError as e:
        print(f"\n{e}", file=sys.stderr)
        if not start_game:
            return 1
        print("Starting with the files you already have.", file=sys.stderr)

    if not start_game:
        return 0

    executable = find_game_executable(config["game_dir"])
    if not executable:
        print("Wow.exe has gone missing from that folder.", file=sys.stderr)
        return 1

    print("Starting the game...")
    subprocess.Popen(launch_command(config, executable), cwd=config["game_dir"])
    return 0


def run_gui(config):
    import queue
    import threading
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    events = queue.Queue()

    root = tk.Tk()
    root.title(config.get("realm_name", "Madosa Launcher"))
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=16)
    frame.grid(sticky="nsew")
    headline = ttk.Label(frame, text="Madosa Realm", font=("TkDefaultFont", 15, "bold"))
    headline.grid(row=0, column=0, columnspan=2, sticky="w")
    status = ttk.Label(frame, text="Starting up...", width=52)
    status.grid(row=1, column=0, columnspan=2, sticky="w", pady=(10, 4))
    progress = ttk.Progressbar(frame, length=380, mode="determinate")
    progress.grid(row=2, column=0, columnspan=2, sticky="we")
    folder = ttk.Label(frame, text="", foreground="#666")
    folder.grid(row=3, column=0, columnspan=2, sticky="w", pady=(6, 12))
    choose = ttk.Button(frame, text="Game folder...")
    choose.grid(row=4, column=0, sticky="w")
    play = ttk.Button(frame, text="Play", state="disabled")
    play.grid(row=4, column=1, sticky="e")

    def show_folder():
        folder.configure(text=config.get("game_dir") or "no game folder chosen yet")

    def worker():
        if not config.get("game_dir"):
            events.put(("status", "Choose your WoW folder to continue."))
            return
        try:
            manifest = update(config, lambda s, p: events.put(("progress", (s, p))))
            if name := manifest.get("name"):
                events.put(("realm", name))
            events.put(("ready", None))
        except UpdateError as e:
            events.put(("status", "Could not update."))
            events.put(("error", str(e)))
            events.put(("ready", None))     # playable with what is already there
        except Exception as e:              # noqa: BLE001
            events.put(("status", "Update failed."))
            events.put(("error", str(e)))

    def start_check():
        play.configure(state="disabled")
        progress.configure(value=0)
        threading.Thread(target=worker, daemon=True).start()

    def drain():
        while True:
            try:
                kind, payload = events.get_nowait()
            except queue.Empty:
                break
            if kind == "progress":
                text, percent = payload
                if text:
                    status.configure(text=text)
                if percent is not None:
                    progress.configure(value=percent)
            elif kind == "status":
                status.configure(text=payload)
            elif kind == "realm":
                headline.configure(text=payload)
                root.title(payload)
            elif kind == "ready":
                play.configure(state="normal")
            elif kind == "error":
                messagebox.showerror("Launcher", payload)
        root.after(100, drain)

    def on_choose():
        chosen = filedialog.askdirectory(title="Select your World of Warcraft folder")
        if not chosen:
            return
        if not find_game_executable(chosen):
            messagebox.showerror("Not a WoW folder", "There is no Wow.exe in that folder.")
            return
        config["game_dir"] = chosen
        save_config(config)
        show_folder()
        start_check()

    def on_play():
        executable = find_game_executable(config["game_dir"])
        if not executable:
            messagebox.showerror("Launcher", "Wow.exe has gone missing from that folder.")
            return
        try:
            subprocess.Popen(launch_command(config, executable), cwd=config["game_dir"])
        except OSError as e:
            messagebox.showerror("Launcher", f"Could not start the game:\n\n{e}")
            return
        root.destroy()

    choose.configure(command=on_choose)
    play.configure(command=on_play)
    show_folder()
    root.after(100, drain)
    start_check()
    root.mainloop()
    return 0


def ask_for_game_dir():
    print("Where is your World of Warcraft folder? (the one with Wow.exe in it)")
    answer = input("> ").strip().strip('"')
    if not answer:
        return None
    if not find_game_executable(answer):
        print("There is no Wow.exe in that folder.", file=sys.stderr)
        return None
    return str(Path(answer).expanduser().resolve())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cli", action="store_true", help="stay on the terminal even if a window is possible")
    ap.add_argument("--check", action="store_true", help="update but do not start the game")
    ap.add_argument("--server", help="realm server URL (remembered for next time)")
    ap.add_argument("--game-dir", help="WoW folder (remembered for next time)")
    args = ap.parse_args()

    config = load_config()
    config.setdefault("server_url", DEFAULT_SERVER_URL)
    if args.server:
        config["server_url"] = args.server
    if args.game_dir:
        config["game_dir"] = args.game_dir
    save_config(config)

    if not args.cli and not args.check:
        try:
            return run_gui(config)
        except ImportError:
            print("No tkinter here - carrying on without a window.", file=sys.stderr)
        except Exception as e:                              # noqa: BLE001
            print(f"No window available ({e}) - carrying on without one.", file=sys.stderr)

    if not config.get("game_dir"):
        game_dir = ask_for_game_dir()
        if not game_dir:
            return 1
        config["game_dir"] = game_dir
        save_config(config)

    return run_cli(config, start_game=not args.check)


if __name__ == "__main__":
    raise SystemExit(main())
