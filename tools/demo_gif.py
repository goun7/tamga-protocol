#!/usr/bin/env python3
"""demo_gif.py — render docs/assets/demo.cast into docs/assets/demo.gif.

Why a GIF next to the cast: the cast plays only in terminal players; a GIF
renders everywhere (README, social, pilot emails). Deterministic: every line of
the cast becomes one frame, held for a fixed delay — no timing jitter.

Usage: python3 tools/demo_gif.py [--cast docs/assets/demo.cast] [--out docs/assets/demo.gif]
Requires Pillow (dev-only dependency; not needed by the runner or the suite).
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

BG = (13, 17, 23)        # terminal-dark
FG = (201, 209, 217)     # soft gray
ACCENT = (88, 166, 255)  # Tamga blue
FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def _load_font(size):
    try:
        from PIL import ImageFont
        for p in FONT_PATHS:
            if Path(p).exists():
                return ImageFont.truetype(p, size)
        return ImageFont.load_default()
    except Exception:
        from PIL import ImageFont
        return ImageFont.load_default()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cast", default="docs/assets/demo.cast")
    ap.add_argument("--out", default="docs/assets/demo.gif")
    ap.add_argument("--cols", type=int, default=100)
    ap.add_argument("--rows", type=int, default=26)
    ap.add_argument("--font-size", type=int, default=14)
    ap.add_argument("--hold-ms", type=int, default=1400)
    a = ap.parse_args()

    lines: list[str] = []
    for raw in Path(a.cast).read_text(encoding="utf-8").splitlines():
        if not raw.startswith("["):
            continue
        try:
            ev = json.loads(raw)
        except Exception:
            continue
        if len(ev) >= 3 and ev[1] == "o":
            for line in ev[2].split("\r\n"):
                line = line.strip("\r")
                if line.strip():
                    lines.append(line)

    if not lines:
        print("demo_gif: no output events found in", a.cast)
        return 1

    font = _load_font(a.font_size)
    cw = font.getbbox("M")[2] - font.getbbox("M")[0] + 1
    ch = a.font_size + 6
    W, H = a.cols * cw + 24, a.rows * ch + 20

    frames: list[Image.Image] = []
    shown = 0
    for line in lines:
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        # window chrome
        d.rectangle([0, 0, W, 8], fill=(30, 34, 40))
        for i, c in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
            d.ellipse([8 + i * 14, 2, 16 + i * 14, 10], fill=c)
        # text window: show last (rows-1) lines up to current
        y = 16
        start = max(0, shown + 1 - (a.rows - 1))
        for i in range(start, shown + 1):
            color = ACCENT if lines[i].lstrip().startswith("#") else FG
            d.text((12, y), lines[i][: a.cols], font=font, fill=color)
            y += ch
        frames.append(img)
        shown += 1

    durations = [a.hold_ms] * len(frames)
    frames[0].save(a.out, save_all=True, append_images=frames[1:],
                   duration=durations, loop=1, optimize=True)
    print(f"demo_gif: {len(frames)} frames -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
