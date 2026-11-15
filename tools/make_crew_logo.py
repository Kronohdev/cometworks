"""Cometlings Crew emblem: a round mission patch in the Cometworks palette.

Builds the layers used by the game's intro (scenes/menu/intro.tscn) and a full emblem:
  ui/brand/crew/ring.png       outer ring with the arched name (transparent centre)
  ui/brand/crew/disc.png       inner sky disc: gradient, stars, the Earth's limb
  ui/brand/crew/comet.png      the comet (head + tail) that circles the patch
  ui/brand/crew/cometling_NN.png  the waving Cometling (frames rendered by
                                  tools/render_crew_cometling.gd)
  ui/brand/crew/emblem.png     everything together (1024 px)
  ui/brand/crew/emblem_2048.png  the same at 2048 px, for print / social

Usage: python tools/make_crew_logo.py <frames_dir>
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui", "brand", "crew")
FONT = os.path.join(ROOT, "ui", "fonts", "fredoka", "Fredoka-Variable.ttf")

S = 2048            # working size
C = S / 2
R_OUT = 1000        # outer edge
R_RING_IN = 770     # inner edge of the cream ring
R_DISC = 740        # sky disc

INK = (43, 42, 92)
SPACE = (30, 29, 74)
SPACE_HI = (70, 52, 140)
CREAM = (255, 246, 230)
BUTTER = (255, 210, 92)
PEACH = (255, 154, 92)
MINT = (111, 224, 190)
ICE = (124, 200, 255)
LILAC = (179, 156, 255)
EARTH = (47, 120, 204)


def font(size, weight="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def circle(d, r, **kw):
    d.ellipse([C - r, C - r, C + r, C + r], **kw)


def arc_text(img, text, radius, center_deg, fnt, fill, top=True, spacing=1.0):
    """Letters along a circle; top=True reads clockwise over the top, False reads
    left to right under the bottom with the letters upright."""
    widths = [fnt.getlength(ch) for ch in text]
    total = sum(widths) * spacing
    span = total / radius            # radians
    a = math.radians(center_deg) - (span / 2 if top else -span / 2)
    for ch, w in zip(text, widths):
        step = w * spacing / radius
        mid = a + (step / 2 if top else -step / 2)
        x = C + radius * math.cos(mid)
        y = C + radius * math.sin(mid)
        rot = math.degrees(mid) + (90 if top else -90)
        size = int(fnt.size * 2)
        tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        td = ImageDraw.Draw(tile)
        td.text((size / 2, size / 2), ch, font=fnt, fill=fill, anchor="mm")
        tile = tile.rotate(-rot, resample=Image.BICUBIC)
        img.alpha_composite(tile, (int(x - size / 2), int(y - size / 2)))
        a += step if top else -step


def star(d, x, y, r, fill, points=4, inner=0.38):
    pts = []
    for i in range(points * 2):
        ang = math.pi * i / points - math.pi / 2
        rr = r if i % 2 == 0 else r * inner
        pts.append((x + rr * math.cos(ang), y + rr * math.sin(ang)))
    d.polygon(pts, fill=fill)


def make_ring():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    circle(d, R_OUT, fill=INK)
    # stitched rim, like an embroidered patch
    r_st = R_OUT - 34
    n = 150
    for i in range(n):
        a0 = math.tau * i / n
        a1 = a0 + math.tau / n * 0.55
        d.line([(C + r_st * math.cos(a0), C + r_st * math.sin(a0)), (C + r_st * math.cos(a1), C + r_st * math.sin(a1))],
               fill=BUTTER, width=7)
    circle(d, R_OUT - 58, fill=(250, 238, 216))
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for k in range(40):
        t = k / 39
        r = (R_OUT - 58) - t * ((R_OUT - 58) - R_RING_IN)
        col = tuple(int(CREAM[i] * (1 - t) + (246, 226, 196)[i] * t) for i in range(3)) + (255,)
        bd.ellipse([C - r, C - r, C + r, C + r], fill=col)
    img.alpha_composite(band)
    d = ImageDraw.Draw(img)
    circle(d, R_RING_IN, fill=INK)
    circle(d, R_RING_IN - 14, fill=BUTTER)
    circle(d, R_RING_IN - 24, fill=INK)
    mask = Image.new("L", (S, S), 255)
    ImageDraw.Draw(mask).ellipse([C - R_DISC, C - R_DISC, C + R_DISC, C + R_DISC], fill=0)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), mask))
    r_text = (R_OUT - 58 + R_RING_IN) / 2
    for dx, dy, col in ((0, 10, (231, 170, 70)), (0, 0, INK)):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        arc_text(layer, "COMETLINGS", r_text, -90, font(140), col, top=True, spacing=1.07)
        arc_text(layer, "CREW", r_text, 90, font(140), col, top=False, spacing=1.2)
        img.alpha_composite(layer, (dx, dy))
    d = ImageDraw.Draw(img)
    for deg in (180, 0):
        x = C + r_text * math.cos(math.radians(deg))
        y = C + r_text * math.sin(math.radians(deg))
        star(d, x, y, 50, PEACH)
        star(d, x, y, 22, BUTTER)
    return img


def make_disc():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = max(0.0, min(1.0, (y - (C - R_DISC)) / (2 * R_DISC)))
        col = tuple(int(SPACE_HI[i] * (1 - t) + SPACE[i] * t) for i in range(3)) + (255,)
        gd.line([(0, y), (S, y)], fill=col)
    d = ImageDraw.Draw(grad)
    rnd = random.Random(7)
    for _ in range(140):
        a = rnd.uniform(0, math.tau)
        r = math.sqrt(rnd.uniform(0, 1)) * (R_DISC - 30)
        x, y = C + r * math.cos(a), C + r * math.sin(a)
        if y > C + 300:
            continue
        s = rnd.choice([3, 4, 5, 6, 8])
        d.ellipse([x - s, y - s, x + s, y + s], fill=(255, 250, 235, rnd.randint(140, 255)))
    for x, y, r in [(C - 470, C - 300, 30), (C + 430, C - 420, 24), (C - 250, C - 560, 18), (C + 560, C - 80, 20)]:
        star(d, x, y, r, CREAM)
    # the Earth's limb along the bottom, with a mint coast and a thin glow
    ec = (C, C + 1180)
    er = 820
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([ec[0] - er - 40, ec[1] - er - 40, ec[0] + er + 40, ec[1] + er + 40], fill=ICE + (150,))
    grad.alpha_composite(glow.filter(ImageFilter.GaussianBlur(28)))
    earth = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(earth)
    ed.ellipse([ec[0] - er, ec[1] - er, ec[0] + er, ec[1] + er], fill=EARTH)
    for cx, cy, rx, ry in [(C - 420, C + 520, 230, 90), (C + 300, C + 470, 250, 110), (C - 20, C + 640, 200, 70), (C + 520, C + 620, 120, 60)]:
        ed.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=MINT)
    emask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(emask).ellipse([ec[0] - er, ec[1] - er, ec[0] + er, ec[1] + er], fill=255)
    grad.paste(earth, (0, 0), emask)
    d = ImageDraw.Draw(grad)
    d.ellipse([ec[0] - er, ec[1] - er, ec[0] + er, ec[1] + er], outline=(170, 225, 255), width=10)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([C - R_DISC, C - R_DISC, C + R_DISC, C + R_DISC], fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def make_comet():
    """A comet sweeping over the upper left of the disc: a tapered two-tone tail."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tail)
    r_path = 600
    a0, a1 = math.radians(150), math.radians(260)   # head at a1
    steps = 90
    for i in range(steps):
        t = i / (steps - 1)
        a = a0 + (a1 - a0) * t
        x, y = C + r_path * math.cos(a), C + r_path * math.sin(a)
        w = 6 + 58 * t ** 1.6
        col = tuple(int(ICE[k] * (1 - t) + MINT[k] * t) for k in range(3)) + (int(60 + 170 * t),)
        td.ellipse([x - w, y - w, x + w, y + w], fill=col)
    tail = tail.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(tail)
    d = ImageDraw.Draw(img)
    hx, hy = C + r_path * math.cos(a1), C + r_path * math.sin(a1)
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([hx - 110, hy - 110, hx + 110, hy + 110], fill=BUTTER + (170,))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(30)))
    d.ellipse([hx - 62, hy - 62, hx + 62, hy + 62], fill=BUTTER)
    d.ellipse([hx - 36, hy - 48, hx + 20, hy + 8], fill=(255, 245, 210))
    star(d, hx, hy, 120, CREAM + (230,), inner=0.18)
    return img


def cometling_frames(frames_dir):
    names = sorted(f for f in os.listdir(frames_dir) if f.startswith("wave_") and f.endswith(".png"))
    ims = [Image.open(os.path.join(frames_dir, n)).convert("RGBA") for n in names]
    box = None
    for im in ims:
        b = im.getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return [im.crop(box) for im in ims]


def place_cometling(img, frame):
    h = 980
    w = int(frame.width * h / frame.height)
    fr = frame.resize((w, h), Image.LANCZOS)
    # a soft drop shadow so the sticker reads on the sky
    sh = Image.new("RGBA", fr.size, (0, 0, 0, 0))
    sh.putalpha(fr.getchannel("A").point(lambda v: int(v * 0.35)))
    pos = (int(C - w / 2), int(C - h / 2 + 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)), (pos[0] + 14, pos[1] + 20))
    img.alpha_composite(fr, pos)


def main():
    """Usage: python tools/make_crew_logo.py <art_dir> (emblem_art_1480.png, emblem_sky_1024.png,
    cometling_art_1024.png rendered from tools/crew_logo_art.py by tools/rasterize_svg.gd)."""
    art_dir = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".png"):
            os.remove(os.path.join(OUT, old))
    ring = make_ring()
    art = Image.open(os.path.join(art_dir, "emblem_art_1480.png")).convert("RGBA")
    full = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    full.alpha_composite(art, (int(C - art.width / 2), int(C - art.height / 2)))
    full.alpha_composite(ring)
    full.save(os.path.join(OUT, "emblem_2048.png"))
    full.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "emblem.png"))
    ring.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "ring.png"))
    Image.open(os.path.join(art_dir, "emblem_sky_1024.png")).save(os.path.join(OUT, "sky.png"))
    Image.open(os.path.join(art_dir, "cometling_art_1024.png")).save(os.path.join(OUT, "cometling.png"))
    print("emblem written to", OUT)


if __name__ == "__main__":
    main()
