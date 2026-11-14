"""Vector art of the Cometworks main menu (GDD section 22.7), written as SVG so Godot
imports it crisply at any size:

  ui/menu/logo_star.svg      the four-point star of the logo (the Cometlings' antenna bulb)
                             that replaces the "O" of COMET
  ui/menu/logo_full.svg      the whole logo as one picture (wordmark drawn as text, for docs,
                             press kits and the README; the game uses scenes/menu/logo.tscn,
                             where every piece is an editable node)
  ui/menu/slider_grabber.svg the throttle-lever grabber of the menu sliders

Run from the repository root:  python tools/build_menu_art.py
Colours are the CwPalette tokens (ui/cometworks_palette.gd).
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "menu")

TEAL = "#3FE0C5"
VIOLET = "#8E7CFF"
IGNITION = "#FF8A3D"
ICE = "#BFE8FF"
TEXT = "#E9EEF7"
SPACE = "#070B14"


def star_path(cx, cy, r_tip, r_waist, bulge=0.32):
    """Four-point star with gently concave sides (quadratic curves through the waist)."""
    pts = []
    for k in range(4):
        a = math.radians(-90 + k * 90)
        tip = (cx + r_tip * math.cos(a), cy + r_tip * math.sin(a))
        b = math.radians(-90 + k * 90 + 45)
        waist = (cx + r_waist * math.cos(b), cy + r_waist * math.sin(b))
        pts.append((tip, waist))
    d = "M %.2f %.2f " % pts[0][0]
    for k in range(4):
        tip_next = pts[(k + 1) % 4][0]
        waist = pts[k][1]
        # control point pulled toward the centre makes the sides concave
        ctrl = (cx + (waist[0] - cx) * bulge, cy + (waist[1] - cy) * bulge)
        d += "Q %.2f %.2f %.2f %.2f " % (ctrl[0], ctrl[1], tip_next[0], tip_next[1])
    return d + "Z"


def logo_star():
    s = 128
    c = s / 2
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{s}" height="{s}" viewBox="0 0 {s} {s}">
  <defs>
    <radialGradient id="core" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="0.45" stop-color="#F2FBFF"/>
      <stop offset="1" stop-color="{ICE}"/>
    </radialGradient>
  </defs>
  <path d="{star_path(c, c, 60, 15, 0.28)}" fill="url(#core)"/>
  <path d="{star_path(c, c, 26, 8, 0.4)}" fill="#FFFFFF"/>
</svg>
'''


def slider_grabber():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="12" height="22" viewBox="0 0 12 22">
  <rect x="1" y="1" width="10" height="20" rx="1.5" fill="#152036" stroke="{ICE}" stroke-width="1.2"/>
  <rect x="3.5" y="9.5" width="5" height="1.2" fill="{ICE}"/>
  <rect x="3.5" y="11.6" width="5" height="1.2" fill="{ICE}"/>
</svg>
'''


def logo_full():
    w, h = 760, 180
    star_x, star_y = 103, 66
    tail = f"M {star_x + 6} {star_y + 22} C 140 124, 260 136, 420 132 S 640 120, 700 112"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <defs>
    <linearGradient id="aurora" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{ICE}"/>
      <stop offset="0.12" stop-color="{TEAL}"/>
      <stop offset="0.55" stop-color="{VIOLET}"/>
      <stop offset="0.9" stop-color="{IGNITION}"/>
      <stop offset="1" stop-color="{IGNITION}" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="{w}" height="{h}" fill="{SPACE}"/>
  <text x="20" y="104" font-family="Bricolage Grotesque, Bahnschrift, Segoe UI, sans-serif" font-weight="600"
        font-size="92" letter-spacing="5" fill="{TEXT}">C</text>
  <path d="{star_path(star_x, star_y, 36, 9, 0.28)}" fill="{ICE}"/>
  <text x="146" y="104" font-family="Bricolage Grotesque, Bahnschrift, Segoe UI, sans-serif" font-weight="600"
        font-size="92" letter-spacing="5" fill="{TEXT}">METWORKS</text>
  <path d="{tail}" fill="none" stroke="url(#aurora)" stroke-width="2.4" stroke-linecap="round"/>
</svg>
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, body in (("logo_star.svg", logo_star()), ("slider_grabber.svg", slider_grabber()),
                       ("logo_full.svg", logo_full())):
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(body)
        print("wrote", os.path.normpath(os.path.join(OUT, name)))


if __name__ == "__main__":
    main()
