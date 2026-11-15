"""The Cometling drawn as illustration (vector art) for the Cometlings Crew emblem.

Writes SVGs that tools/rasterize_svg.gd turns into PNGs:
  cometling_art.svg   the waving Cometling alone (transparent)
  emblem_art.svg      the inner art of the patch: nebula sky, stars, comet, Moon, the Cometling
Reference: the engineer Cometling of the game (hard hat with a star, antenna star, big eyes,
blush, white belly, brown shorts, comet-tipped ear). Usage: python tools/crew_logo_art.py <out_dir>
"""
import math
import os
import random
import sys

INK = "#2b2a5c"
SKIN, SKIN_SH, SKIN_HI = "#f7c592", "#de9466", "#ffe6c8"
HAT, HAT_SH, HAT_HI = "#ffd25c", "#e3a12c", "#fff2b0"
SHORTS, SHORTS_SH = "#b06a3c", "#7d4527"
CREAM = "#fff6e6"
BLUSH = "#ff8fb8"
TIP = "#7cc8ff"
SW = 11  # outline width


def star_path(cx, cy, r, inner=0.42, points=4, rot=-90):
    pts = []
    for i in range(points * 2):
        a = math.radians(rot + 180 * i / points)
        rr = r if i % 2 == 0 else r * inner
        pts.append("%.1f,%.1f" % (cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return "M" + " L".join(pts) + " Z"


def soft_star(cx, cy, r):
    """A 4-point star with curved sides (a sparkle)."""
    k = r * 0.18
    return ("M{cx},{t} Q{a},{a2} {r_},{cy} Q{a},{b2} {cx},{b} Q{c},{b2} {l},{cy} Q{c},{a2} {cx},{t} Z"
            .format(cx=cx, cy=cy, t=cy - r, b=cy + r, l=cx - r, r_=cx + r, a=cx + k, c=cx - k, a2=cy - k, b2=cy + k))


def cometling(ox=0.0, oy=0.0, s=1.0):
    """The Cometling, about 620 x 760 units around (500, 520) before the transform."""
    o = SW
    return f"""
<g transform="translate({ox} {oy}) scale({s})" stroke-linejoin="round" stroke-linecap="round">
  <defs>
    <radialGradient id="skin" cx="38%" cy="32%" r="75%">
      <stop offset="0" stop-color="{SKIN_HI}"/><stop offset="0.45" stop-color="{SKIN}"/><stop offset="1" stop-color="{SKIN_SH}"/>
    </radialGradient>
    <radialGradient id="hat" cx="35%" cy="25%" r="80%">
      <stop offset="0" stop-color="{HAT_HI}"/><stop offset="0.5" stop-color="{HAT}"/><stop offset="1" stop-color="{HAT_SH}"/>
    </radialGradient>
    <radialGradient id="iris" cx="50%" cy="75%" r="70%">
      <stop offset="0" stop-color="#9d8cff"/><stop offset="0.6" stop-color="#5b4bd6"/><stop offset="1" stop-color="#2f2683"/>
    </radialGradient>
    <linearGradient id="tip" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{SKIN}"/><stop offset="0.55" stop-color="{SKIN}"/><stop offset="0.7" stop-color="{TIP}"/><stop offset="1" stop-color="#3f9be8"/>
    </linearGradient>
    <radialGradient id="shade" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="{SKIN_SH}" stop-opacity="0.55"/><stop offset="1" stop-color="{SKIN_SH}" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="headclip"><ellipse cx="500" cy="420" rx="238" ry="214"/></clipPath>
    <clipPath id="bodyclip"><path d="M392,610 C380,700 395,790 500,800 C605,790 620,700 608,610 Z"/></clipPath>
  </defs>

  <!-- back ear -->
  <path d="M300,300 C250,250 235,190 262,170 C300,175 330,230 345,280 Z" fill="url(#skin)" stroke="{INK}" stroke-width="{o}"/>

  <!-- arm down (right side) -->
  <path d="M590,650 C630,680 650,720 655,760" fill="none" stroke="{INK}" stroke-width="{58 + 2 * o}"/>
  <path d="M590,650 C630,680 650,720 655,760" fill="none" stroke="{SKIN}" stroke-width="58"/>
  <circle cx="660" cy="778" r="40" fill="{CREAM}" stroke="{INK}" stroke-width="{o}"/>
  <path d="M640,790 Q660,805 682,788" fill="none" stroke="#e6d3b3" stroke-width="6"/>

  <!-- feet -->
  <path d="M398,842 C392,812 420,800 452,804 C484,808 492,830 488,850 C470,868 412,868 398,842 Z" fill="url(#skin)" stroke="{INK}" stroke-width="{o}"/>
  <path d="M512,850 C508,830 516,808 548,804 C580,800 608,812 602,842 C588,868 530,868 512,850 Z" fill="url(#skin)" stroke="{INK}" stroke-width="{o}"/>
  <path d="M404,846 C430,860 470,860 486,848" fill="none" stroke="{CREAM}" stroke-width="9"/>
  <path d="M514,848 C530,860 570,860 596,846" fill="none" stroke="{CREAM}" stroke-width="9"/>

  <!-- body -->
  <path d="M392,610 C380,700 395,790 500,800 C605,790 620,700 608,610 Z" fill="url(#skin)" stroke="{INK}" stroke-width="{o}"/>
  <g clip-path="url(#bodyclip)">
    <ellipse cx="497" cy="700" rx="78" ry="72" fill="{CREAM}"/>
    <ellipse cx="470" cy="672" rx="26" ry="16" fill="#ffffff" opacity="0.8"/>
    <rect x="380" y="748" width="240" height="70" fill="{SHORTS}"/>
    <rect x="380" y="796" width="240" height="22" fill="{SHORTS_SH}"/>
    <path d="M370,748 L630,748" stroke="{INK}" stroke-width="7"/>
    <rect x="482" y="750" width="34" height="24" rx="6" fill="{HAT}" stroke="{INK}" stroke-width="5"/>
  </g>
  <path d="M392,610 C380,700 395,790 500,800 C605,790 620,700 608,610" fill="none" stroke="{INK}" stroke-width="{o}"/>

  <!-- waving arm (left side, raised) -->
  <path d="M412,655 C340,650 268,628 232,585" fill="none" stroke="{INK}" stroke-width="{60 + 2 * o}"/>
  <path d="M412,655 C340,650 268,628 232,585" fill="none" stroke="{SKIN}" stroke-width="60"/>
  <circle cx="214" cy="556" r="48" fill="{CREAM}" stroke="{INK}" stroke-width="{o}"/>
  <path d="M188,536 Q186,518 202,506" fill="none" stroke="#e6d3b3" stroke-width="7"/>
  <path d="M150,540 Q136,524 142,504" fill="none" stroke="{INK}" stroke-width="6" opacity="0.75"/>
  <path d="M140,590 Q118,584 112,562" fill="none" stroke="{INK}" stroke-width="6" opacity="0.5"/>
  <path d="M178,476 Q192,462 212,462" fill="none" stroke="{INK}" stroke-width="6" opacity="0.6"/>

  <!-- head -->
  <ellipse cx="500" cy="420" rx="238" ry="214" fill="url(#skin)" stroke="{INK}" stroke-width="{o}"/>
  <g clip-path="url(#headclip)">
    <ellipse cx="640" cy="600" rx="300" ry="210" fill="url(#shade)"/>
    <ellipse cx="380" cy="300" rx="120" ry="70" fill="#ffffff" opacity="0.22"/>
  </g>
  <!-- blush -->
  <ellipse cx="352" cy="492" rx="44" ry="26" fill="{BLUSH}" opacity="0.75"/>
  <ellipse cx="652" cy="492" rx="44" ry="26" fill="{BLUSH}" opacity="0.75"/>
  <path d="M332,488 l10,-10 M352,490 l10,-10 M372,492 l8,-8" stroke="#ffffff" stroke-width="4" opacity="0.6"/>
  <!-- eyes -->
  <g>
    <ellipse cx="418" cy="430" rx="56" ry="66" fill="{INK}"/>
    <ellipse cx="418" cy="446" rx="44" ry="46" fill="url(#iris)"/>
    <ellipse cx="400" cy="406" rx="22" ry="25" fill="#ffffff"/>
    <circle cx="438" cy="466" r="9" fill="#ffffff"/>
    <path d="{soft_star(392, 452, 9)}" fill="#ffffff" opacity="0.85"/>
    <ellipse cx="584" cy="430" rx="56" ry="66" fill="{INK}"/>
    <ellipse cx="584" cy="446" rx="44" ry="46" fill="url(#iris)"/>
    <ellipse cx="566" cy="406" rx="22" ry="25" fill="#ffffff"/>
    <circle cx="604" cy="466" r="9" fill="#ffffff"/>
    <path d="{soft_star(558, 452, 9)}" fill="#ffffff" opacity="0.85"/>
  </g>
  <!-- mouth -->
  <path d="M468,492 Q501,488 534,492 Q530,532 501,534 Q472,532 468,492 Z" fill="#8f1f3d" stroke="{INK}" stroke-width="7"/>
  <path d="M482,520 Q501,508 520,520 Q512,532 501,532 Q490,532 482,520 Z" fill="#ff7c9c"/>

  <!-- front ear with its comet tip -->
  <path d="M705,330 C760,300 820,292 846,312 C850,340 790,372 720,378 Z" fill="url(#tip)" stroke="{INK}" stroke-width="{o}"/>
  <path d="M800,306 l18,-22 M830,318 l26,-10" stroke="{TIP}" stroke-width="7" opacity="0.8"/>

  <!-- hard hat -->
  <path d="M286,330 C280,210 380,150 500,150 C620,150 720,210 714,330 Z" fill="url(#hat)" stroke="{INK}" stroke-width="{o}"/>
  <path d="M500,152 C520,200 524,280 520,330" fill="none" stroke="{HAT_SH}" stroke-width="10" opacity="0.7"/>
  <path d="M340,250 C352,205 398,178 446,170" fill="none" stroke="{HAT_HI}" stroke-width="14" opacity="0.9"/>
  <path d="M232,348 C240,322 360,308 500,308 C640,308 768,322 772,350 C770,378 640,388 500,386 C360,386 236,376 232,348 Z"
        fill="url(#hat)" stroke="{INK}" stroke-width="{o}"/>
  <path d="M262,350 C320,366 680,368 744,350" fill="none" stroke="{HAT_SH}" stroke-width="9" opacity="0.7"/>
  <path d="{star_path(452, 262, 38, 0.45, 4)}" fill="{CREAM}" stroke="{INK}" stroke-width="7"/>
  <!-- antenna -->
  <path d="M528,152 C534,128 540,108 548,88" fill="none" stroke="{INK}" stroke-width="{12 + 2 * o}"/>
  <path d="M528,152 C534,128 540,108 548,88" fill="none" stroke="{HAT_SH}" stroke-width="12"/>
  <path d="{star_path(552, 70, 44, 0.42, 5)}" fill="{HAT}" stroke="{INK}" stroke-width="8"/>
  <path d="{star_path(552, 70, 18, 0.42, 5)}" fill="{HAT_HI}"/>
</g>"""


def emblem_inner():
    rnd = random.Random(12)
    stars = []
    for _ in range(170):
        a = rnd.uniform(0, math.tau)
        r = math.sqrt(rnd.uniform(0, 1)) * 480
        x, y = 500 + r * math.cos(a), 500 + r * math.sin(a)
        if y > 760:
            continue
        s = rnd.choice([1.4, 1.8, 2.2, 2.8, 3.4])
        stars.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{s}" fill="#fff8e8" opacity="{rnd.uniform(0.45, 1):.2f}"/>')
    sparkles = "".join(f'<path d="{soft_star(x, y, r)}" fill="#fff6e6"/>' for x, y, r in
                       [(170, 300, 16), (820, 250, 20), (760, 470, 12), (240, 520, 10), (650, 140, 12), (130, 430, 8)])
    return f"""
<defs>
  <radialGradient id="sky" cx="50%" cy="30%" r="75%">
    <stop offset="0" stop-color="#5a3fa8"/><stop offset="0.55" stop-color="#2f2670"/><stop offset="1" stop-color="#171640"/>
  </radialGradient>
  <radialGradient id="neb1" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ff8fb8" stop-opacity="0.55"/><stop offset="1" stop-color="#ff8fb8" stop-opacity="0"/></radialGradient>
  <radialGradient id="neb2" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#6fe0be" stop-opacity="0.45"/><stop offset="1" stop-color="#6fe0be" stop-opacity="0"/></radialGradient>
  <radialGradient id="neb3" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#7cc8ff" stop-opacity="0.45"/><stop offset="1" stop-color="#7cc8ff" stop-opacity="0"/></radialGradient>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#fff2b0" stop-opacity="1"/><stop offset="0.35" stop-color="#ffd25c" stop-opacity="0.75"/><stop offset="1" stop-color="#ff9a5c" stop-opacity="0"/></radialGradient>
  <linearGradient id="tail" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#7cc8ff" stop-opacity="0"/><stop offset="0.6" stop-color="#6fe0be" stop-opacity="0.55"/><stop offset="1" stop-color="#fff6e6" stop-opacity="0.95"/>
  </linearGradient>
  <linearGradient id="tail2" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#ff8fb8" stop-opacity="0"/><stop offset="1" stop-color="#ffd25c" stop-opacity="0.8"/>
  </linearGradient>
  <radialGradient id="moon" cx="40%" cy="20%" r="80%">
    <stop offset="0" stop-color="#f4ecff"/><stop offset="0.6" stop-color="#c9bdf0"/><stop offset="1" stop-color="#8f80c8"/>
  </radialGradient>
  <clipPath id="disc"><circle cx="500" cy="500" r="500"/></clipPath>
</defs>
<g clip-path="url(#disc)">
  <rect width="1000" height="1000" fill="url(#sky)"/>
  <ellipse cx="250" cy="330" rx="330" ry="210" fill="url(#neb1)"/>
  <ellipse cx="760" cy="420" rx="300" ry="240" fill="url(#neb2)"/>
  <ellipse cx="560" cy="170" rx="360" ry="170" fill="url(#neb3)"/>
  {''.join(stars)}
  {sparkles}
  <!-- the comet sweeping over the top: two tails and a glowing head -->
  <path d="M-20,560 C90,330 320,170 645,148 C470,175 290,290 150,520 C110,560 40,600 -20,560 Z" fill="url(#tail)"/>
  <path d="M30,690 C150,420 360,230 645,150 C430,250 280,380 170,600 C130,660 70,720 30,690 Z" fill="url(#tail2)" opacity="0.5"/>
  <path d="M120,420 C260,260 430,180 645,148" fill="none" stroke="#fff6e6" stroke-width="3" opacity="0.55"/>
  <path d="M60,470 C200,300 400,200 645,149" fill="none" stroke="#fff6e6" stroke-width="2" opacity="0.35"/>
  <circle cx="655" cy="148" r="110" fill="url(#glow)"/>
  <circle cx="655" cy="148" r="30" fill="#fffbe8"/>
  <path d="{soft_star(655, 148, 78)}" fill="#ffffff" opacity="0.9"/>
  <!-- the Moon's curve to stand on, with craters -->
  <ellipse cx="500" cy="1270" rx="760" ry="430" fill="url(#moon)" stroke="{INK}" stroke-width="10"/>
  <ellipse cx="300" cy="905" rx="56" ry="18" fill="#a597d8"/>
  <ellipse cx="700" cy="930" rx="70" ry="20" fill="#a597d8"/>
  <ellipse cx="520" cy="975" rx="40" ry="12" fill="#a597d8"/>
  <ellipse cx="420" cy="880" rx="260" ry="34" fill="#ffffff" opacity="0.35"/>
</g>"""


def cometling_part(part, ox=95, oy=140, s=0.82):
    """'body' = the Cometling without the raised arm, 'arm' = the raised arm alone (no motion
    lines), both placed in the sky disc's 1000-unit frame like the emblem."""
    full = cometling(ox, oy, s)
    a = full.index("  <!-- waving arm")
    b = full.index("  <!-- head -->")
    head_part, arm, rest = full[:a], full[a:b], full[b:]
    if part == "body":
        return head_part + rest
    arm = "\n".join(l for l in arm.splitlines() if 'opacity="0.' not in l)
    defs_end = head_part.index("</defs>") + len("</defs>")
    return head_part[:defs_end] + "\n" + arm + "\n</g>"


def brazil_flag():
    """The Brazilian flag as a cartoon cloth, 300 x 210 units, pole side on the right."""
    return f"""
<g stroke-linejoin="round">
  <defs>
    <linearGradient id="clothshade" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#000" stop-opacity="0.12"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.10"/><stop offset="1" stop-color="#000" stop-opacity="0.08"/>
    </linearGradient>
    <clipPath id="cloth"><rect x="12" y="12" width="276" height="186" rx="14"/></clipPath>
  </defs>
  <rect x="12" y="12" width="276" height="186" rx="14" fill="#1fa84f"/>
  <g clip-path="url(#cloth)">
    <path d="M150,30 L268,105 L150,180 L32,105 Z" fill="#ffd93b" stroke="#e8b800" stroke-width="4"/>
    <circle cx="150" cy="105" r="46" fill="#1d3f9e"/>
    <path d="M106,96 C130,84 172,86 196,104 L194,116 C170,98 130,96 104,108 Z" fill="#fff6e6"/>
    <circle cx="132" cy="122" r="3" fill="#fff6e6"/><circle cx="150" cy="130" r="3.5" fill="#fff6e6"/>
    <circle cx="168" cy="124" r="3" fill="#fff6e6"/><circle cx="160" cy="138" r="2.5" fill="#fff6e6"/>
    <circle cx="140" cy="138" r="2.5" fill="#fff6e6"/><circle cx="176" cy="112" r="2" fill="#fff6e6"/>
    <rect x="12" y="12" width="276" height="186" fill="url(#clothshade)"/>
  </g>
  <rect x="12" y="12" width="276" height="186" rx="14" fill="none" stroke="{INK}" stroke-width="{SW}"/>
</g>"""


def flag_pole():
    """A pole 24 x 420 units with a star finial."""
    return f"""
<g stroke-linejoin="round" stroke-linecap="round">
  <rect x="26" y="40" width="18" height="370" rx="9" fill="#e9e1f7" stroke="{INK}" stroke-width="8"/>
  <rect x="30" y="48" width="5" height="350" rx="2" fill="#ffffff" opacity="0.8"/>
  <path d="{star_path(35, 30, 26, 0.45, 5)}" fill="{HAT}" stroke="{INK}" stroke-width="6"/>
</g>"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">'
    with open(os.path.join(out, "cometling_art.svg"), "w", encoding="utf-8") as f:
        f.write(head + cometling() + "</svg>")
    with open(os.path.join(out, "emblem_art.svg"), "w", encoding="utf-8") as f:
        f.write(head + emblem_inner() + cometling(95, 140, 0.82) + "</svg>")
    with open(os.path.join(out, "emblem_sky.svg"), "w", encoding="utf-8") as f:
        f.write(head + emblem_inner() + "</svg>")
    for part in ("body", "arm"):
        with open(os.path.join(out, "intro_%s.svg" % part), "w", encoding="utf-8") as f:
            f.write(head + cometling_part(part) + "</svg>")
    with open(os.path.join(out, "intro_flag.svg"), "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 210" width="300" height="210">' + brazil_flag() + "</svg>")
    with open(os.path.join(out, "intro_pole.svg"), "w", encoding="utf-8") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 70 420" width="70" height="420">' + flag_pole() + "</svg>")
    print("svgs written to", out)


if __name__ == "__main__":
    main()
