#!/usr/bin/env python3
"""Draw a layout snapshot from snapshot.lua as a PNG, with the client's font.

The Lua side resolves the anchors and measures the strings; this only puts
ink where those rectangles say. That is the point: if the picture looks wrong,
the layout is wrong, not the drawing.

What is honestly approximate: Blizzard's backdrop art is a flat fill and a
one-pixel border here, buttons are drawn as plain boxes, and icons are drawn
as an empty frame. Text position, size, wrapping and colour are real.

Usage: render.py [<snapshot dir>] [<out dir>] [--scale N]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = os.path.expanduser(
    "~/Games/world-of-warcraft-wrath-of-the-lich-king/drive_c/"
    "world_of_warcraft_wrath_of_the_lich_king/fonts/frizqt__.ttf")

# The colour a GameFont* object carries when nothing calls SetTextColor.
FONT_COLOR = {
    "GameFontNormal": (1.0, 0.82, 0.0), "GameFontNormalSmall": (1.0, 0.82, 0.0),
    "GameFontNormalLarge": (1.0, 0.82, 0.0), "GameFontNormalHuge": (1.0, 0.82, 0.0),
    "GameFontHighlight": (1.0, 1.0, 1.0), "GameFontHighlightSmall": (1.0, 1.0, 1.0),
    "GameFontHighlightLarge": (1.0, 1.0, 1.0),
    "GameFontDisable": (0.5, 0.5, 0.5), "GameFontDisableSmall": (0.5, 0.5, 0.5),
}
BORDER = {"DialogBox": (110, 90, 58), "Tooltip": (95, 95, 105)}


def font_path():
    for candidate in (FONT, FONT + ".disabled"):
        if os.path.exists(candidate):
            return candidate
    raise SystemExit("no FRIZQT__.TTF at %s" % FONT)


def rgb(c, alpha=255):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), alpha)


def render(snapshot, path, scale=2, pad=24):
    widgets = snapshot["widgets"]
    if not widgets:
        raise SystemExit("nothing showing in %s" % path)
    screen_h = snapshot["screen"]["height"]

    # crop to what is drawn, with a margin
    left = min(w["left"] for w in widgets) - pad
    right = max(w["right"] for w in widgets) + pad
    bottom = min(w["bottom"] for w in widgets) - pad
    top = max(w["top"] for w in widgets) + pad

    W, H = int((right - left) * scale), int((top - bottom) * scale)
    img = Image.new("RGBA", (W, H), (26, 24, 30, 255))
    draw = ImageDraw.Draw(img, "RGBA")

    def X(x):
        return (x - left) * scale

    def Y(y):                      # WoW counts up from the bottom, images down
        return (top - y) * scale

    fonts = {}

    def face(size):
        key = round(size * scale)
        if key not in fonts:
            fonts[key] = ImageFont.truetype(font_path(), key)
        return fonts[key]

    for w in widgets:
        x0, y0, x1, y1 = X(w["left"]), Y(w["top"]), X(w["right"]), Y(w["bottom"])
        kind, template = w["kind"], w.get("template", "")

        if w.get("backdrop") is not None:
            fill = rgb(w["backdropColor"], int(w["backdropColor"][3] * 255))
            edge = next((c for k, c in BORDER.items() if k in w["backdrop"]), (120, 120, 120))
            draw.rectangle([x0, y0, x1, y1], fill=fill, outline=edge + (255,), width=max(1, scale))

        elif kind == "Texture":
            tex = w.get("texture") or []
            numbers = [t for t in tex if _isnum(t)]
            if len(numbers) >= 3:
                a = float(numbers[3]) if len(numbers) > 3 else 1.0
                draw.rectangle([x0, y0, x1, y1],
                               fill=rgb([float(n) for n in numbers[:3]], int(a * 255)))
            elif tex:                        # an icon path: show the space it takes
                draw.rectangle([x0, y0, x1, y1], outline=(150, 140, 110, 255), width=max(1, scale))
                draw.line([x0, y0, x1, y1], fill=(80, 75, 60, 255), width=1)
                draw.line([x0, y1, x1, y0], fill=(80, 75, 60, 255), width=1)

        elif kind == "Button" and template == "UIPanelCloseButton":
            cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2 - 2 * scale
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(170, 150, 110, 255),
                         width=max(1, scale))
            d = r * 0.45
            for a, b in (((-d, -d), (d, d)), ((-d, d), (d, -d))):
                draw.line([cx + a[0], cy + a[1], cx + b[0], cy + b[1]],
                          fill=(200, 190, 160, 255), width=max(1, scale))

        elif kind == "Button" and template:
            draw.rectangle([x0, y0, x1, y1], fill=(58, 54, 50, 255),
                           outline=(140, 128, 100, 255), width=max(1, scale))
            if w.get("text"):
                f = face(11)
                t = w["text"]
                tw = draw.textlength(t, font=f)
                draw.text(((x0 + x1 - tw) / 2, (y0 + y1) / 2 - f.size * 0.62), t,
                          font=f, fill=(255, 210, 100, 255))

        if kind == "FontString" and w.get("lines"):
            f = face(w["size"])
            base = rgb(FONT_COLOR.get(w.get("font", ""), (1, 1, 1)))
            if w.get("color"):
                base = rgb(w["color"])
            line_h = (w["top"] - w["bottom"]) / max(1, len(w["lines"])) * scale
            for i, runs in enumerate(w["lines"]):
                width = sum(draw.textlength(r["text"], font=f) for r in runs)
                if w.get("justify") == "CENTER":
                    x = (x0 + x1 - width) / 2
                elif w.get("justify") == "RIGHT":
                    x = x1 - width
                else:
                    x = x0
                y = y0 + i * line_h
                for run in runs:
                    colour = rgb(run["color"]) if run.get("color") else base
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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    scale = 2
    for a in sys.argv[1:]:
        if a.startswith("--scale"):
            scale = int(a.split("=")[1]) if "=" in a else 2
    here = os.path.dirname(os.path.abspath(__file__))
    src = args[0] if args else os.path.join(here, "snapshots")
    dst = args[1] if len(args) > 1 else src

    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if not name.endswith(".json"):
            continue
        snapshot = json.load(open(os.path.join(src, name)))
        out = os.path.join(dst, name[:-5] + ".png")
        render(snapshot, out, scale=scale)
        print("  %s  (%d widgets)" % (os.path.relpath(out), len(snapshot["widgets"])))


if __name__ == "__main__":
    main()
