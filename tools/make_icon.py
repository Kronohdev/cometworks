"""App and site icon: the voxel Cometling's head (tools/render_icon_head.gd) on a rounded
night-sky tile. Writes ui/brand/icon/icon.png (1024, the project icon), ui/brand/icon/icon.ico
(the Windows exe icon) and the site icons into <site_dir>.
Usage: python tools/make_icon.py <head_png> <site_dir>"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui", "brand", "icon")
S = 1024

def tile():
    t = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(t)
    top, bot = (98, 70, 184), (30, 29, 74)
    for y in range(S):
        k = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] * (1 - k) + bot[i] * k) for i in range(3)) + (255,))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([180, 120, 844, 784], fill=(255, 210, 92, 70))
    t.alpha_composite(glow.filter(ImageFilter.GaussianBlur(90)))
    d = ImageDraw.Draw(t)
    for x, y, r in [(150, 170, 9), (880, 210, 7), (120, 600, 6), (900, 640, 8), (780, 110, 5)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 246, 230, 220))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=220, fill=255)
    t.putalpha(mask)
    return t, mask

def main():
    head = Image.open(sys.argv[1]).convert("RGBA")
    site = sys.argv[2]
    os.makedirs(OUT, exist_ok=True); os.makedirs(site, exist_ok=True)
    box = head.getbbox()
    head = head.crop((box[0], box[1], box[2], box[3]))
    w = 900
    head = head.resize((w, int(head.height * w / head.width)), Image.LANCZOS)
    t, mask = tile()
    # a soft shadow and the head, its body running off the bottom edge
    pos = ((S - w) // 2, 150)
    sh = Image.new("RGBA", head.size, (10, 8, 30, 0)); sh.putalpha(head.getchannel("A").point(lambda v: v * 120 // 255))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)), (pos[0] + 10, pos[1] + 18))
    layer.alpha_composite(head, pos)
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0)); clipped.paste(layer, (0, 0), mask)
    t.alpha_composite(clipped)
    rim = ImageDraw.Draw(t); rim.rounded_rectangle([6, 6, S - 7, S - 7], radius=214, outline=(43, 42, 92, 255), width=12)
    t.save(os.path.join(OUT, "icon.png"))
    t.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    t.save(os.path.join(site, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
    for n, sz in [("favicon-16.png", 16), ("favicon-32.png", 32), ("apple-touch-icon.png", 180), ("icon-192.png", 192), ("icon-512.png", 512)]:
        t.resize((sz, sz), Image.LANCZOS).save(os.path.join(site, n))
    print("icons written")

if __name__ == "__main__":
    main()
