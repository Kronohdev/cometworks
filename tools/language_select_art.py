"""Art of the language screen (scenes/menu/language_select.tscn), in the style of the intro flag
(tools/crew_logo_art.py: flat cartoon fills, soft gradients, thick ink outline).

Writes SVGs that tools/rasterize_svg.gd turns into the PNGs in ui/menu/language/:
  flag_us.svg    the US flag as a cartoon cloth, 300 x 210 like intro_flag.svg, drawn *mirrored*
                 (canton top right) because the wave shader keeps the pole on the texture's
                 right edge; the scene flips the sprite so the pole sits on the left
  podium.svg     the round pedestal a flag stands on, 300 x 190
  moon.svg       the Moon's curve the Cometling walks on, 2800 x 420 (ellipse rx 1500, ry 640,
                 top at y 40: LanguageSelect.MOON_* mirror these numbers)
  rock.svg       a little floating asteroid with a crystal, 220 x 170
  planet.svg     a ringed planet for the sky, 360 x 240
Usage: python tools/language_select_art.py <out_dir>
       godot --headless --path . --script res://tools/rasterize_svg.gd -- <out_dir>/flag_us.svg ui/menu/language/flag_us.png 1.5
"""
import os
import random
import sys

from crew_logo_art import INK, SW, soft_star, star_path

CREAM = "#fff6e6"


def us_flag():
    """The US flag as a cartoon cloth, mirrored (canton on the right = the pole side)."""
    x0, y0, w, h = 12, 12, 276, 186
    stripes = []
    sh = h / 13.0
    for i in range(13):
        if i % 2 == 0:
            stripes.append(f'<rect x="{x0}" y="{y0 + i * sh:.2f}" width="{w}" height="{sh + 0.4:.2f}" fill="#e8424f"/>')
    cw, ch = w * 0.42, sh * 7
    cx0 = x0 + w - cw
    stars = []
    rows = [6, 5, 6, 5, 6]
    for r, n in enumerate(rows):
        yy = y0 + ch * (r + 0.75) / (len(rows) + 0.5)
        for k in range(n):
            off = 0.0 if n == 6 else 0.5
            xx = cx0 + 4 + (cw - 14) * (k + 0.5 + off) / 6.0
            stars.append(f'<path d="{star_path(xx, yy, 6.2, 0.45, 5)}" fill="{CREAM}"/>')
    return f"""
<g stroke-linejoin="round">
  <defs>
    <linearGradient id="clothshade" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="0.08"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.10"/><stop offset="1" stop-color="#000" stop-opacity="0.12"/>
    </linearGradient>
    <clipPath id="cloth"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="14"/></clipPath>
  </defs>
  <rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="14" fill="{CREAM}"/>
  <g clip-path="url(#cloth)">
    {''.join(stripes)}
    <rect x="{cx0:.2f}" y="{y0}" width="{cw:.2f}" height="{ch:.2f}" fill="#2c4aa8"/>
    {''.join(stars)}
    <rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="url(#clothshade)"/>
  </g>
  <rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="14" fill="none" stroke="{INK}" stroke-width="{SW}"/>
</g>"""


def podium():
    """A round two-step pedestal seen a little from above, 300 x 190."""
    return f"""
<g stroke-linejoin="round" stroke-linecap="round">
  <defs>
    <linearGradient id="side" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#8f80c8"/><stop offset="0.35" stop-color="#c9bdf0"/><stop offset="0.6" stop-color="#b3a5e6"/><stop offset="1" stop-color="#7a6bb8"/>
    </linearGradient>
    <linearGradient id="base" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#6f60ad"/><stop offset="0.4" stop-color="#a597d8"/><stop offset="1" stop-color="#5f519c"/>
    </linearGradient>
    <radialGradient id="top" cx="40%" cy="35%" r="70%">
      <stop offset="0" stop-color="#ffffff"/><stop offset="0.6" stop-color="#fff6e6"/><stop offset="1" stop-color="#eadff7"/>
    </radialGradient>
  </defs>
  <!-- base step -->
  <path d="M18,128 L18,150 A132,30 0 0 0 282,150 L282,128 Z" fill="url(#base)" stroke="{INK}" stroke-width="9"/>
  <ellipse cx="150" cy="128" rx="132" ry="30" fill="#c9bdf0" stroke="{INK}" stroke-width="9"/>
  <!-- drum -->
  <path d="M48,60 L48,122 A102,24 0 0 0 252,122 L252,60 Z" fill="url(#side)" stroke="{INK}" stroke-width="9"/>
  <path d="M60,74 L60,116" stroke="#ffffff" stroke-width="7" opacity="0.55"/>
  <ellipse cx="150" cy="60" rx="102" ry="24" fill="url(#top)" stroke="{INK}" stroke-width="9"/>
  <ellipse cx="128" cy="55" rx="46" ry="8" fill="#ffffff" opacity="0.8"/>
</g>"""


def moon():
    """The top of the Moon: an ellipse rx 1500 ry 640 centred at (1400, 680), clipped to 2800 x 420."""
    rnd = random.Random(7)
    craters = []
    for x, y, rx in [(520, 150, 70), (980, 110, 46), (1260, 200, 90), (1720, 120, 54), (2140, 170, 78),
                     (760, 300, 110), (1560, 320, 70), (2420, 300, 96), (340, 330, 80), (1960, 360, 60)]:
        ry = rx * 0.28
        craters.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry:.1f}" fill="#a597d8"/>'
                       f'<ellipse cx="{x}" cy="{y - ry * 0.35:.1f}" rx="{rx * 0.82:.1f}" ry="{ry * 0.6:.1f}" fill="#9384cc"/>'
                       f'<path d="M{x - rx * 0.9:.1f},{y + ry * 0.2:.1f} A{rx:.1f},{ry:.1f} 0 0 0 {x + rx * 0.9:.1f},{y + ry * 0.2:.1f}" '
                       f'fill="none" stroke="#e9e1fb" stroke-width="5" opacity="0.8"/>')
    pebbles = "".join(f'<circle cx="{rnd.uniform(150, 2650):.0f}" cy="{rnd.uniform(90, 400):.0f}" r="{rnd.choice([4, 5, 7])}" '
                      f'fill="#8f80c8" opacity="0.7"/>' for _ in range(40))
    return f"""
<defs>
  <radialGradient id="moon" cx="50%" cy="0%" r="70%">
    <stop offset="0" stop-color="#f4ecff"/><stop offset="0.45" stop-color="#cfc4f2"/><stop offset="1" stop-color="#8576c2"/>
  </radialGradient>
  <clipPath id="disc"><ellipse cx="1400" cy="680" rx="1500" ry="640"/></clipPath>
  <linearGradient id="dark" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1e1d4a" stop-opacity="0"/><stop offset="1" stop-color="#1e1d4a" stop-opacity="0.55"/>
  </linearGradient>
</defs>
<g clip-path="url(#disc)">
<ellipse cx="1400" cy="680" rx="1500" ry="640" fill="url(#moon)"/>
{''.join(craters)}
{pebbles}
<ellipse cx="1400" cy="80" rx="700" ry="34" fill="#ffffff" opacity="0.32"/>
<rect x="0" y="180" width="2800" height="240" fill="url(#dark)"/>
</g>
<ellipse cx="1400" cy="680" rx="1500" ry="640" fill="none" stroke="{INK}" stroke-width="12"/>"""


def rock():
    """A little floating asteroid with a mint crystal, 220 x 170."""
    return f"""
<g stroke-linejoin="round" stroke-linecap="round">
  <defs>
    <radialGradient id="rock" cx="35%" cy="30%" r="80%">
      <stop offset="0" stop-color="#d9cff7"/><stop offset="0.55" stop-color="#a597d8"/><stop offset="1" stop-color="#6f60ad"/>
    </radialGradient>
    <linearGradient id="gem" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ddf7ee"/><stop offset="0.5" stop-color="#6fe0be"/><stop offset="1" stop-color="#2fa889"/>
    </linearGradient>
  </defs>
  <path d="M30,92 C26,64 60,50 92,56 C120,40 168,46 186,72 C206,92 196,124 168,138 C140,158 84,160 56,142 C36,130 32,112 30,92 Z"
        fill="url(#rock)" stroke="{INK}" stroke-width="9"/>
  <ellipse cx="82" cy="110" rx="18" ry="9" fill="#8f80c8"/>
  <ellipse cx="146" cy="118" rx="12" ry="6" fill="#8f80c8"/>
  <ellipse cx="96" cy="74" rx="34" ry="8" fill="#ffffff" opacity="0.5"/>
  <path d="M120,62 L132,20 L150,14 L156,58 Z" fill="url(#gem)" stroke="{INK}" stroke-width="7"/>
  <path d="M132,20 L140,58" stroke="#ffffff" stroke-width="4" opacity="0.7"/>
  <path d="{soft_star(170, 26, 12)}" fill="{CREAM}"/>
</g>"""


def planet():
    """A ringed planet (peach, with a lilac ring), 360 x 240."""
    return f"""
<g stroke-linejoin="round" stroke-linecap="round">
  <defs>
    <radialGradient id="pl" cx="35%" cy="30%" r="80%">
      <stop offset="0" stop-color="#ffe0c2"/><stop offset="0.5" stop-color="#ff9a5c"/><stop offset="1" stop-color="#d6407e"/>
    </radialGradient>
  </defs>
  <ellipse cx="180" cy="122" rx="160" ry="38" fill="none" stroke="{INK}" stroke-width="22" transform="rotate(-14 180 122)"/>
  <ellipse cx="180" cy="122" rx="160" ry="38" fill="none" stroke="#b39cff" stroke-width="10" transform="rotate(-14 180 122)"/>
  <circle cx="180" cy="120" r="84" fill="url(#pl)" stroke="{INK}" stroke-width="9"/>
  <path d="M110,92 C150,80 210,82 254,100" fill="none" stroke="#ffffff" stroke-width="9" opacity="0.35"/>
  <path d="M104,140 C150,152 220,150 258,134" fill="none" stroke="#d6407e" stroke-width="9" opacity="0.35"/>
  <g transform="rotate(-14 180 122)">
    <path d="M20,122 A160,38 0 0 0 340,122" fill="none" stroke="{INK}" stroke-width="22"/>
    <path d="M20,122 A160,38 0 0 0 340,122" fill="none" stroke="#b39cff" stroke-width="10"/>
  </g>
</g>"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    files = {
        "flag_us.svg": (300, 210, us_flag()),
        "podium.svg": (300, 190, podium()),
        "moon.svg": (2800, 420, moon()),
        "rock.svg": (220, 170, rock()),
        "planet.svg": (360, 240, planet()),
    }
    for name, (w, h, body) in files.items():
        with open(os.path.join(out, name), "w", encoding="utf-8") as f:
            f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>')
    print("svgs written to", out)


if __name__ == "__main__":
    main()
