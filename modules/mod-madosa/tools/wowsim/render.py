#!/usr/bin/env python3
"""Draw a layout snapshot as a PNG, with the client's own fonts and art.

The Lua side resolves the anchors and measures the strings; this only puts ink
where those rectangles say. If the picture looks wrong, the layout is wrong.

Backdrops are drawn the way the game draws them: the bgFile tiled or stretched
inside the insets, and the edgeFile - one strip of eight tiles, left, right,
top, bottom and the four corners - laid round the outside. Fonts are the faces
extract.py measured, so what is drawn is what was measured.

A texture the art folder does not have is fetched from the client when one is
given with --client, so an addon using art nobody extracted yet still draws.

Usage: render.py [<snapshot dir>] [<out dir>] [--scale N] [--client DIR]
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "art")
FACES = os.path.join(ART, "fonts")

# A backdrop edge strip is eight tiles wide, in this order. All four edges are
# stored as vertical strips - the top and bottom ones are laid on their side
# when drawn, which is why they are rotated here and the corners are not.
EDGE_ORDER = ["left", "right", "top", "bottom",
              "topleft", "topright", "bottomleft", "bottomright"]
ROTATED_EDGES = ("top", "bottom")

BUTTON_ART = {
    "UIPanelCloseButton": "UI-Panel-MinimizeButton-Up",
    "UIPanelButtonTemplate": "UI-Panel-Button-Up",
    "UIPanelButtonTemplate2": "UI-Panel-Button-Up",
    "OptionsButtonTemplate": "UI-Panel-Button-Up",
}

_cache = {}
_client = None


def texture(name):
    """A decoded texture by its file stem, from art/, or out of the client."""
    if not name:
        return None
    stem = name.replace("/", "\\").rsplit("\\", 1)[-1]
    if stem.lower().endswith(".blp"):
        stem = stem[:-4]
    if stem in _cache:
        return _cache[stem]
    path = os.path.join(ART, stem + ".png")
    img = None
    if os.path.exists(path):
        img = Image.open(path).convert("RGBA")
    elif _client is not None:
        sys.path.insert(0, HERE)
        import blp
        data = _client.read(name.replace("/", "\\") + ".blp") or _client.read(name)
        if data:
            img = blp.decode(data)
            img.save(path)
    _cache[stem] = img
    return img


def tile(target, img, box):
    """Repeat img across box, the way a tiled backdrop repeats."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    if x1 <= x0 or y1 <= y0:
        return
    patch = Image.new("RGBA", (x1 - x0, y1 - y0))
    for y in range(0, y1 - y0, img.height):
        for x in range(0, x1 - x0, img.width):
            patch.alpha_composite(img, (x, y))
    target.alpha_composite(patch, (x0, y0))


def stretch(target, img, box):
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    if x1 <= x0 or y1 <= y0:
        return
    target.alpha_composite(img.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))


def draw_backdrop(img, w, box, scale):
    x0, y0, x1, y1 = box
    edge_size = (w.get("edgeSize") or 16) * scale

    fill = texture(w.get("backdropFill"))
    if fill is not None:
        inset = edge_size * 0.35
        tinted = fill
        colour = w.get("backdropColor")
        if colour:
            layer = Image.new("RGBA", fill.size,
                              tuple(int(c * 255) for c in colour[:3]) + (255,))
            tinted = Image.composite(layer, fill, Image.new("L", fill.size, 255))
            tinted.putalpha(fill.getchannel("A").point(
                lambda a: int(a * (colour[3] if len(colour) > 3 else 1))))
        tile(img, tinted, (x0 + inset, y0 + inset, x1 - inset, y1 - inset))

    border = texture(w.get("backdrop"))
    if border is None:
        return
    piece = border.width // 8
    tiles = {}
    for i, name in enumerate(EDGE_ORDER):
        art = border.crop((i * piece, 0, (i + 1) * piece, border.height))
        if name in ROTATED_EDGES:
            # the line inside the tile has to end up against the outside of the
            # frame, which is clockwise for the top edge and the other way for
            # the bottom one
            art = art.transpose(Image.ROTATE_270 if name == "top" else Image.ROTATE_90)
        tiles[name] = art
    e = edge_size
    tile(img, tiles["top"], (x0 + e, y0, x1 - e, y0 + e))
    tile(img, tiles["bottom"], (x0 + e, y1 - e, x1 - e, y1))
    tile(img, tiles["left"], (x0, y0 + e, x0 + e, y1 - e))
    tile(img, tiles["right"], (x1 - e, y0 + e, x1, y1 - e))
    stretch(img, tiles["topleft"], (x0, y0, x0 + e, y0 + e))
    stretch(img, tiles["topright"], (x1 - e, y0, x1, y0 + e))
    stretch(img, tiles["bottomleft"], (x0, y1 - e, x0 + e, y1))
    stretch(img, tiles["bottomright"], (x1 - e, y1 - e, x1, y1))


def render(snapshot, path, scale=2, pad=24):
    widgets = snapshot["widgets"]
    if not widgets:
        raise SystemExit("nothing showing in %s" % path)

    left = min(w["left"] for w in widgets) - pad
    right = max(w["right"] for w in widgets) + pad
    bottom = min(w["bottom"] for w in widgets) - pad
    top = max(w["top"] for w in widgets) + pad

    img = Image.new("RGBA", (int((right - left) * scale), int((top - bottom) * scale)),
                    (22, 20, 26, 255))
    draw = ImageDraw.Draw(img, "RGBA")

    def X(x):
        return (x - left) * scale

    def Y(y):                      # WoW counts up from the bottom, images down
        return (top - y) * scale

    fonts = {}

    def face(name, size):
        key = (name, round(size * scale))
        if key not in fonts:
            path_ = os.path.join(FACES, name or "frizqt__.ttf")
            if not os.path.exists(path_):
                path_ = os.path.join(FACES, "frizqt__.ttf")
            fonts[key] = ImageFont.truetype(path_, key[1])
        return fonts[key]

    for w in widgets:
        box = (X(w["left"]), Y(w["top"]), X(w["right"]), Y(w["bottom"]))
        kind, template = w["kind"], w.get("template", "")

        if w.get("backdrop") is not None or w.get("backdropFill"):
            draw_backdrop(img, w, box, scale)

        elif kind == "Texture":
            tex = w.get("texture") or []
            numbers = [t for t in tex if _isnum(t)]
            if len(numbers) >= 3:
                alpha = float(numbers[3]) if len(numbers) > 3 else 1.0
                draw.rectangle(box, fill=tuple(int(float(n) * 255) for n in numbers[:3])
                               + (int(alpha * 255),))
            elif tex:
                art = texture(tex[0])
                if art is not None:
                    stretch(img, art, box)
                else:
                    draw.rectangle(box, outline=(150, 140, 110, 255), width=max(1, scale))

        elif kind == "Button" and template in BUTTON_ART:
            art = texture(BUTTON_ART[template])
            if art is not None:
                if template == "UIPanelCloseButton":
                    stretch(img, art, box)
                else:
                    # the button strip is up/down side by side; take the left half
                    up = art.crop((0, 0, art.width // 2, art.height))
                    stretch(img, up, box)
            else:
                draw.rectangle(box, fill=(58, 54, 50, 255), outline=(140, 128, 100, 255))
            if w.get("text"):
                f = face(w.get("face"), w.get("size", 11))
                width = draw.textlength(w["text"], font=f)
                draw.text(((box[0] + box[2] - width) / 2, (box[1] + box[3]) / 2 - f.size * 0.62),
                          w["text"], font=f, fill=(255, 210, 100, 255))

        if kind == "FontString" and w.get("lines"):
            f = face(w.get("face"), w["size"])
            base = tuple(int(c * 255) for c in (w.get("fontColor") or [1, 1, 1])) + (255,)
            if w.get("color"):
                base = tuple(int(c * 255) for c in w["color"]) + (255,)
            line_h = (w["top"] - w["bottom"]) / max(1, len(w["lines"])) * scale
            for i, runs in enumerate(w["lines"]):
                width = sum(draw.textlength(r["text"], font=f) for r in runs)
                if w.get("justify") == "CENTER":
                    x = (box[0] + box[2] - width) / 2
                elif w.get("justify") == "RIGHT":
                    x = box[2] - width
                else:
                    x = box[0]
                y = box[1] + i * line_h
                for run in runs:
                    colour = tuple(int(c * 255) for c in run["color"]) + (255,) \
                        if run.get("color") else base
                    draw.text((x + scale, y + scale), run["text"], font=f,
                              fill=(0, 0, 0, 160))            # the shadow every GameFont has
                    draw.text((x, y), run["text"], font=f, fill=colour)
                    x += draw.textlength(run["text"], font=f)

    img.convert("RGB").save(path)
    return path


def _isnum(v):
    try:
        float(v)
        return True
    except (TypeError, ValueError):
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?", default=os.path.join(HERE, "snapshots"))
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--client")
    args = ap.parse_args()

    if args.client:
        global _client
        sys.path.insert(0, HERE)
        import mpq
        data = os.path.join(args.client, "data")
        _client = mpq.Client(data if os.path.isdir(data) else os.path.join(args.client, "Data"))

    dst = args.dst or args.src
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(args.src)):
        if not name.endswith(".json"):
            continue
        snapshot = json.load(open(os.path.join(args.src, name)))
        out = os.path.join(dst, name[:-5] + ".png")
        render(snapshot, out, scale=args.scale)
        print("  %s  (%d widgets)" % (os.path.relpath(out), len(snapshot["widgets"])))


if __name__ == "__main__":
    main()
