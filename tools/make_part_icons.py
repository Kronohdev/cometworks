"""Builds the hangar palette icons (ui/part_icons/<model>.png) from the Godot renders
in docs/hangar_renders/: keys out the dark render background and fits each model in
a transparent square.

Usage: python tools/make_part_icons.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "hangar_renders"
OUT = ROOT / "ui" / "part_icons"
SIZE = 128
PAD = 8


def icon(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    bg = im[2, 2]
    diff = np.abs(im - bg).max(axis=2)
    alpha = np.clip((diff - 6.0) / 22.0, 0, 1)
    rgba = np.dstack([im, alpha * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    img.thumbnail((SIZE - 2 * PAD, SIZE - 2 * PAD), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, ((SIZE - img.width) // 2, (SIZE - img.height) // 2), img)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in sorted(SRC.glob("*.png")):
        if p.stem.endswith("_assembled"):
            continue
        icon(p).save(OUT / p.name)
        n += 1
    print(f"{n} icons -> {OUT}")


if __name__ == "__main__":
    main()
