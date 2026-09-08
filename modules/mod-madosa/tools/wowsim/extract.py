#!/usr/bin/env python3
"""Pull out of a WoW 3.3.5 client everything the harness needs to be faithful.

Three things, none of which can be guessed well:

  fonts   Fonts.xml and FontStyles.xml define every GameFont* object - which
          TTF, what pixel height, what colour, whether it is outlined. The
          harness needs those to lay text out and to draw it in the right
          colour, and an addon that asks for a font object by name gets the
          real one.
  metrics The glyph advances of every TTF those font objects name, at every
          size they use. This is what makes wrapping real rather than guessed.
  art     The backdrop, button and border textures, decoded from BLP to PNG,
          so a rendered snapshot looks like the game and not like a wireframe.

Archives are read straight out of the client with mpq.py, honouring the patch
order, so what comes out is what that install actually shows - custom UI
patches included.

Usage: extract.py [--client <dir>] [fonts|metrics|art|icons <name>...|all]
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import blp                                                    # noqa: E402
import mpq                                                    # noqa: E402

DEFAULT_CLIENT = os.path.expanduser(
    "~/Games/world-of-warcraft-wrath-of-the-lich-king/drive_c/"
    "world_of_warcraft_wrath_of_the_lich_king")

FONT_XML = [r"Interface\FrameXML\Fonts.xml", r"Interface\FrameXML\FontStyles.xml"]

# The textures the renderer draws with. A backdrop's edgeFile is one strip of
# eight tiles - left, right, top, bottom, then the four corners - which is why
# a 32px border arrives 256 wide.
ART = [
    r"Interface\DialogFrame\UI-DialogBox-Background.blp",
    r"Interface\DialogFrame\UI-DialogBox-Border.blp",
    r"Interface\DialogFrame\UI-DialogBox-Gold-Background.blp",
    r"Interface\DialogFrame\UI-DialogBox-Gold-Border.blp",
    r"Interface\Tooltips\UI-Tooltip-Background.blp",
    r"Interface\Tooltips\UI-Tooltip-Border.blp",
    r"Interface\Buttons\UI-Panel-Button-Up.blp",
    r"Interface\Buttons\UI-Panel-Button-Down.blp",
    r"Interface\Buttons\UI-Panel-Button-Disabled.blp",
    r"Interface\Buttons\UI-Panel-Button-Highlight.blp",
    r"Interface\Buttons\UI-Panel-MinimizeButton-Up.blp",
    r"Interface\Buttons\UI-Panel-MinimizeButton-Down.blp",
    r"Interface\Buttons\UI-Panel-MinimizeButton-Highlight.blp",
    r"Interface\Buttons\WHITE8X8.blp",
    r"Interface\Buttons\UI-Quickslot2.blp",
    r"Interface\Tooltips\UI-StatusBar-Border.blp",
]


# --------------------------------------------------------------------------
# Fonts
# --------------------------------------------------------------------------

def parse_fonts(client):
    """Every <Font> in Fonts.xml and FontStyles.xml, with inheritance resolved."""
    raw = {}
    order = []
    for path in FONT_XML:
        blob = client.read(path)
        if blob is None:
            raise SystemExit("%s is not in this client" % path)
        text = blob.decode("utf-8", "replace")
        for match in re.finditer(r'<Font\s+([^>]*?)(/>|>(.*?)</Font>)', text, re.S):
            attrs, body = match.group(1), match.group(3) or ""
            name = re.search(r'name="([^"]+)"', attrs)
            if not name:
                continue
            entry = {"inherits": None, "font": None, "size": None,
                     "color": None, "outline": None, "shadow": None}
            inherits = re.search(r'inherits="([^"]+)"', attrs)
            if inherits:
                entry["inherits"] = inherits.group(1)
            font = re.search(r'font="([^"]+)"', attrs)
            if font:
                entry["font"] = font.group(1)
            outline = re.search(r'outline="([^"]+)"', attrs)
            if outline:
                entry["outline"] = outline.group(1)
            height = re.search(r'<FontHeight>\s*<AbsValue val="([\d.]+)"', body, re.S)
            if height:
                entry["size"] = float(height.group(1))
            # the first <Color> outside <Shadow> is the text colour
            without_shadow = re.sub(r"<Shadow>.*?</Shadow>", "", body, flags=re.S)
            colour = re.search(r'<Color r="([\d.]+)" g="([\d.]+)" b="([\d.]+)"', without_shadow)
            if colour:
                entry["color"] = [float(colour.group(i)) for i in (1, 2, 3)]
            if re.search(r"<Shadow>", body):
                entry["shadow"] = True
            if name.group(1) not in raw:
                order.append(name.group(1))
            raw[name.group(1)] = entry

    resolved = {}

    def resolve(name, seen=()):
        if name in resolved:
            return resolved[name]
        entry = raw.get(name)
        if entry is None or name in seen:
            return {"font": r"Fonts\FRIZQT__.TTF", "size": 12, "color": [1, 1, 1],
                    "outline": None, "shadow": False}
        base = resolve(entry["inherits"], seen + (name,)) if entry["inherits"] else {
            "font": r"Fonts\FRIZQT__.TTF", "size": 12, "color": [1, 1, 1],
            "outline": None, "shadow": False}
        out = {
            "font": entry["font"] or base["font"],
            "size": entry["size"] or base["size"],
            "color": entry["color"] or base["color"],
            "outline": entry["outline"] or base["outline"],
            "shadow": entry["shadow"] if entry["shadow"] is not None else base["shadow"],
        }
        resolved[name] = out
        return out

    for name in order:
        resolve(name)
    return resolved, order


def write_fonts(fonts, order, path):
    lines = [
        "-- Generated by extract.py from the client's Fonts.xml and FontStyles.xml.",
        "-- FontObjects[name] = { font = <ttf>, size = <px>, color = {r,g,b},",
        "--                      outline = <NORMAL|THICK|nil>, shadow = <bool> }",
        "-- These are the real GameFont* objects, so a frame that asks for one by",
        "-- name is measured and drawn the way the client would.",
        "",
        "FontObjects = {",
    ]
    for name in order:
        f = fonts[name]
        colour = "{ %s }" % ", ".join("%g" % c for c in f["color"])
        outline = '"%s"' % f["outline"] if f["outline"] else "nil"
        lines.append('    ["%s"] = { font = "%s", size = %g, color = %s, outline = %s, shadow = %s },'
                     % (name, f["font"].replace("\\", "\\\\"), f["size"], colour,
                        outline, "true" if f["shadow"] else "false"))
    lines += ["}", ""]
    open(path, "w").write("\n".join(lines))
    return len(order)


# --------------------------------------------------------------------------

def do_fonts(client, out_dir):
    fonts, order = parse_fonts(client)
    n = write_fonts(fonts, order, os.path.join(out_dir, "fonts.lua"))
    sizes = sorted({(f["font"].rsplit("\\", 1)[-1].lower(), f["size"]) for f in fonts.values()})
    print("fonts: %d objects, %d distinct face/size pairs" % (n, len(sizes)))
    return fonts


def do_metrics(client, fonts, out_dir, client_dir):
    import fontmetrics
    wanted = {}
    for f in fonts.values():
        face = f["font"].rsplit("\\", 1)[-1].lower()
        wanted.setdefault(face, set()).add(int(round(f["size"])))
    # sizes an addon may set by hand on top of the ones the font objects use
    for face in wanted:
        wanted[face] |= {8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24}
    fontmetrics.write(wanted, client_dir, client, os.path.join(out_dir, "fontmetrics.lua"),
                      face_dir=os.path.join(HERE, "art", "fonts"))


def do_art(client, names, art_dir):
    os.makedirs(art_dir, exist_ok=True)
    got, missing = 0, []
    for path in names:
        data = client.read(path)
        if data is None:
            missing.append(path)
            continue
        name = path.rsplit("\\", 1)[-1]
        if name.lower().endswith(".blp"):
            name = name[:-4]
        try:
            blp.decode(data).save(os.path.join(art_dir, name + ".png"))
        except Exception as exc:                       # a texture we cannot read is not fatal
            missing.append("%s (%s)" % (path, exc))
            continue
        got += 1
    print("art: %d textures -> %s" % (got, os.path.relpath(art_dir)))
    for m in missing:
        print("  missing: %s" % m)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="*", default=["all"],
                    help="fonts, metrics, art, icons <name>..., or all")
    ap.add_argument("--client", default=DEFAULT_CLIENT)
    args = ap.parse_args()

    data_dir = os.path.join(args.client, "data")
    if not os.path.isdir(data_dir):
        data_dir = os.path.join(args.client, "Data")
    client = mpq.Client(data_dir)
    print("client: %d archives under %s" % (len(client.archives), data_dir))

    what = args.what or ["all"]
    out_dir = os.path.join(HERE, "data")
    art_dir = os.path.join(HERE, "art")

    if what[0] == "icons":
        do_art(client, [r"Interface\Icons\%s.blp" % n for n in what[1:]], art_dir)
        return

    want = set(what)
    fonts = None
    if "all" in want or "fonts" in want or "metrics" in want:
        fonts = do_fonts(client, out_dir)
    if "all" in want or "metrics" in want:
        do_metrics(client, fonts, out_dir, args.client)
    if "all" in want or "art" in want:
        do_art(client, ART, art_dir)


if __name__ == "__main__":
    main()
