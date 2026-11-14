"""MARGIN UI kit 2.0 — single source of the project palette and of the UI look.

PALETTE below is the one place where the game's colours live. This script writes:
  ui/kit/*.svg            9-patch frames (panels, cards, buttons, inputs, knobs, switches),
                          line icons (actions, markers, part categories, stats, symmetry
                          modes) and the original MARGIN mission emblem
  ui/margin_theme.tres    the Godot Theme used by every HUD (hangar, map, surfaces, flight)
  ui/palette.gd           class MarginPalette (palette constants for scripts)
  docs/art/palette.md     token table + usage rules (EN/PT)
  docs/art/palette_swatches.svg
tools/build_vab_scene.py imports PALETTE/LIGHTS for the building materials and lights.
Edit the palette here, re-run this script, then re-import in Godot.

Usage: python tools/make_ui_kit.py
"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "ui" / "kit"

# ---------------------------------------------------------------- the MARGIN palette 2.0
# name: (hex, role). Groups are only for docs; every name must be unique.
PALETTE = {
    # --- surfaces (cool graphite, dark UI over bright worlds) — darkest to lightest
    "INK":         ("#0a0e13", "deepest background; text on accent fills"),
    "WELL":        ("#0e141b", "inset wells: inputs, tracks, tool groups"),
    "PANEL":       ("#121922", "panel / sheet body (surface)"),
    "PANEL_HI":    ("#18212c", "panel gradient top, top-bar"),
    "RAISED":      ("#1c2633", "raised surface: cards, buttons"),
    "RAISED_HI":   ("#263345", "hovered raised surface"),
    # --- strokes
    "LINE":        ("#2b3949", "1 px strokes, separators, inactive outlines"),
    "LINE_HI":     ("#435670", "strong strokes, hovered outlines"),
    # --- text
    "TEXT":        ("#edf2f7", "primary text, icons"),
    "TEXT_DIM":    ("#93a3b8", "secondary text, captions"),
    "TEXT_MUTED":  ("#5f6f84", "disabled, placeholders, off toggles"),
    # --- accents
    "ACCENT":      ("#ff9a3d", "Signal Orange: brand, selection, primary action"),
    "ACCENT_HI":   ("#ffbd7a", "Signal Orange lifted: hover, text on dark tint"),
    "ACCENT_LO":   ("#c8661a", "Signal Orange deep: pressed primary, strokes"),
    "ACCENT_2":    ("#6aa9ff", "Mission Blue: info, focus, progress, section labels"),
    "ACCENT_2_HI": ("#a3c9ff", "Mission Blue lifted"),
    # --- status
    "SUCCESS":     ("#5bd68e", "go / OK / good TWR"),
    "WARNING":     ("#ffc547", "caution, marginal values"),
    "DANGER":      ("#ff5f6d", "no-go, errors, red beacons"),
    # --- data series (charts, stage colours): distinct from markers and status
    "DATA_1":      ("#6aa9ff", "series 1 (blue)"),
    "DATA_2":      ("#ff9a3d", "series 2 (orange)"),
    "DATA_3":      ("#4fd6b0", "series 3 (teal)"),
    "DATA_4":      ("#b590ff", "series 4 (violet)"),
    "DATA_5":      ("#f47fa4", "series 5 (rose)"),
    "DATA_6":      ("#c9d36a", "series 6 (lime)"),
    # --- world materials (hangar building; see docs/art/palette.md)
    "STRUCTURE":   ("#dfe3e7", "VAB White: walls, ceiling, enclosures"),
    "METAL":       ("#a3adb8", "Light steel: columns, trusses, towers, rails"),
    "GUNMETAL":    ("#3c4450", "Gunmetal: grating, pad base, machinery"),
    "HAZARD":      ("#f2b705", "Safety yellow: crane, handrails, edges, floor lanes"),
    "GLASS":       ("#bfe9ff", "Cleanroom light: emissive panels, windows, glass"),
}
# KSP-convention marker colours: reserved, never used by the UI chrome or the world.
MARKERS = {
    "MARK_COM": ("#ffd91a", "Center of Mass (yellow)"),
    "MARK_COT": ("#f233d9", "Center of Thrust (magenta)"),
    "MARK_COL": ("#33bfff", "Center of Lift (cyan)"),
}
# light colours (not UI tokens; correlated colour temperatures used by every lamp)
LIGHTS = {
    "LAMP_WARM": ("#ffe2bf", "3500 K high-bay lamps, work lights"),
    "LAMP_COOL": ("#e4efff", "6000 K fill, wall wash"),
    "SUN":       ("#fff1dc", "daylight sun through the door"),
}
GROUPS = [
    ("Surfaces / superfícies", ["INK", "WELL", "PANEL", "PANEL_HI", "RAISED", "RAISED_HI"]),
    ("Strokes / contornos", ["LINE", "LINE_HI"]),
    ("Text / texto", ["TEXT", "TEXT_DIM", "TEXT_MUTED"]),
    ("Accents / acentos", ["ACCENT", "ACCENT_HI", "ACCENT_LO", "ACCENT_2", "ACCENT_2_HI"]),
    ("Status", ["SUCCESS", "WARNING", "DANGER"]),
    ("Data / dados", ["DATA_1", "DATA_2", "DATA_3", "DATA_4", "DATA_5", "DATA_6"]),
    ("Markers / marcadores (reserved)", list(MARKERS)),
    ("World / mundo", ["STRUCTURE", "METAL", "GUNMETAL", "HAZARD", "GLASS"]),
    ("Lights / luzes", list(LIGHTS)),
]


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def P(name):
    return (PALETTE.get(name) or MARKERS.get(name) or LIGHTS[name])[0]


def mix(a, b, t):
    """Hex colour between a and b (t = 0 -> a, 1 -> b)."""
    ra, rb = hexrgb(a), hexrgb(b)
    return "#" + "".join(f"{round((x + (y - x) * t) * 255):02x}" for x, y in zip(ra, rb))


def lum(h):
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in hexrgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


INK, WELL, PANEL, PANEL_HI = P("INK"), P("WELL"), P("PANEL"), P("PANEL_HI")
RAISED, RAISED_HI, LINE, LINE_HI = P("RAISED"), P("RAISED_HI"), P("LINE"), P("LINE_HI")
TEXT, DIM, MUTED = P("TEXT"), P("TEXT_DIM"), P("TEXT_MUTED")
ACCENT, ACCENT_HI, ACCENT_LO = P("ACCENT"), P("ACCENT_HI"), P("ACCENT_LO")
ACCENT2, ACCENT2_HI = P("ACCENT_2"), P("ACCENT_2_HI")
ICON = "#ffffff"  # icons are white: buttons tint them through icon_*_color


# ================================================================== SVG helpers
def svg(w, h, body, out_w=None, out_h=None):
    ow, oh = out_w or w, out_h or h
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{ow}" height="{oh}" viewBox="0 0 {w} {h}">'
            f'{body}</svg>\n')


_gid = [0]


def vgrad(top, bottom, op_top=1.0, op_bottom=1.0):
    """Returns (defs, url) of a vertical gradient."""
    _gid[0] += 1
    gid = f"g{_gid[0]}"
    d = (f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
         f'<stop offset="0" stop-color="{top}" stop-opacity="{op_top}"/>'
         f'<stop offset="1" stop-color="{bottom}" stop-opacity="{op_bottom}"/></linearGradient></defs>')
    return d, f"url(#{gid})"


def frame(w, h, r, top, bottom, stroke=None, stroke_op=1.0, fill_op=1.0, pad=4, glow=None, glow_op=0.4,
          shadow=0.0, hi_op=0.06, stripe=None, tick=None):
    """A rounded 9-patch frame: gradient body, crisp 1 px stroke, 1 px top highlight,
    optional outer glow / drop shadow drawn into `pad` (use expand margins = pad)."""
    W, H = w + 2 * pad, h + 2 * pad
    b = ""
    if shadow > 0:
        for k in range(pad, 0, -1):
            op = shadow * (1.0 - k / (pad + 1)) ** 2
            b += (f'<rect x="{pad - k * 0.8:.1f}" y="{pad - k * 0.6 + 2:.1f}" width="{w + k * 1.6:.1f}" '
                  f'height="{h + k * 1.4:.1f}" rx="{r + k}" fill="#000000" fill-opacity="{op:.3f}"/>')
    if glow:
        for k in range(pad, 0, -1):
            op = glow_op * (1.0 - k / (pad + 1)) ** 1.6
            b += (f'<rect x="{pad + 0.5 - k}" y="{pad + 0.5 - k}" width="{w - 1 + 2 * k}" height="{h - 1 + 2 * k}" '
                  f'rx="{r + k - 0.5}" fill="none" stroke="{glow}" stroke-opacity="{op:.3f}" stroke-width="1"/>')
    d, url = vgrad(top, bottom, fill_op, fill_op)
    b += d
    st = f' stroke="{stroke}" stroke-opacity="{stroke_op}" stroke-width="1"' if stroke else ""
    b += f'<rect x="{pad + 0.5}" y="{pad + 0.5}" width="{w - 1}" height="{h - 1}" rx="{r - 0.5}" fill="{url}"{st}/>'
    if hi_op > 0:
        b += (f'<path d="M{pad + r},{pad + 1.5} H{pad + w - r}" stroke="#ffffff" stroke-opacity="{hi_op}" '
              f'stroke-width="1"/>')
    if stripe:
        b += f'<rect x="{pad + 1}" y="{pad + r * 0.7:.1f}" width="2.5" height="{h - r * 1.4:.1f}" rx="1.25" fill="{stripe}"/>'
    if tick:
        b += f'<rect x="{pad + r + 4}" y="{pad}" width="22" height="2" rx="1" fill="{tick}"/>'
    return svg(W, H, b)


# ------------------------------------------------------------------ frames (9-patch)
# (file, svg, texture margin, expand margin) — margins also go into the theme below.
FRAMES = {}


def add_frame(name, body, margin, expand):
    FRAMES[name] = (body, margin, expand)


def build_frames():
    # glass panel: gradient, top highlight, orange tick, soft drop shadow
    add_frame("panel_frame", frame(96, 96, 12, PANEL_HI, PANEL, LINE, 1.0, 0.93, pad=14, shadow=0.16,
                                   hi_op=0.07, tick=ACCENT), 28, 14)
    # top bar: same glass, slimmer radius, accent underline glow
    tb = frame(128, 52, 12, PANEL_HI, INK, LINE, 1.0, 0.94, pad=12, shadow=0.15, hi_op=0.07)
    d = (f'<defs><linearGradient id="ul" x1="0" y1="0" x2="1" y2="0">'
         f'<stop offset="0" stop-color="{ACCENT}" stop-opacity="0"/>'
         f'<stop offset="0.5" stop-color="{ACCENT}" stop-opacity="0.9"/>'
         f'<stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/></linearGradient></defs>'
         f'<rect x="30" y="{12 + 52 - 1.5}" width="{128 - 36}" height="1" fill="url(#ul)"/>')
    add_frame("topbar_frame", tb.replace("</svg>", d + "</svg>"), 26, 12)
    # readout / floating glass pill
    add_frame("readout_frame", frame(96, 64, 14, PANEL_HI, PANEL, LINE_HI, 0.8, 0.94, pad=12, shadow=0.18,
                                     hi_op=0.08), 27, 12)
    # cards
    add_frame("card_frame", frame(64, 64, 9, RAISED, mix(RAISED, PANEL, 0.6), LINE, 1.0, 0.96, pad=2,
                                  hi_op=0.05, stripe=ACCENT), 12, 2)
    add_frame("card_plain", frame(64, 64, 9, RAISED, mix(RAISED, PANEL, 0.6), LINE, 1.0, 0.96, pad=2,
                                  hi_op=0.05), 12, 2)
    add_frame("card_hover", frame(64, 64, 9, RAISED_HI, RAISED, ACCENT2, 0.85, 1.0, pad=4, glow=ACCENT2,
                                  glow_op=0.35, hi_op=0.08), 14, 4)
    add_frame("card_selected", frame(64, 64, 9, mix(RAISED, ACCENT, 0.22), mix(RAISED, ACCENT, 0.12), ACCENT,
                                     0.9, 1.0, pad=4, glow=ACCENT, glow_op=0.3, hi_op=0.08), 14, 4)
    # buttons (normal / hover / toggled on / disabled)
    add_frame("btn_normal", frame(48, 32, 8, RAISED, mix(RAISED, PANEL, 0.5), LINE, 1.0, pad=4), 12, 4)
    add_frame("btn_hover", frame(48, 32, 8, RAISED_HI, RAISED, LINE_HI, 1.0, pad=4, glow=ACCENT2,
                                 glow_op=0.28, hi_op=0.09), 12, 4)
    add_frame("btn_pressed", frame(48, 32, 8, mix(RAISED, ACCENT, 0.24), mix(RAISED, ACCENT, 0.14), ACCENT,
                                   0.85, pad=4, hi_op=0.08), 12, 4)
    add_frame("btn_pressed_hover", frame(48, 32, 8, mix(RAISED, ACCENT, 0.32), mix(RAISED, ACCENT, 0.2),
                                         ACCENT_HI, 0.9, pad=4, glow=ACCENT, glow_op=0.32, hi_op=0.1), 12, 4)
    add_frame("btn_disabled", frame(48, 32, 8, mix(RAISED, PANEL, 0.5), PANEL, LINE, 0.6, 0.7, pad=4, hi_op=0), 12, 4)
    # flat (ghost) buttons inside tool groups
    add_frame("flat_hover", frame(48, 32, 7, RAISED_HI, RAISED, LINE_HI, 0.8, pad=4, hi_op=0.08), 11, 4)
    # primary action (Launch)
    add_frame("btn_primary", frame(48, 32, 8, ACCENT_HI, ACCENT, ACCENT_LO, 0.9, pad=4, glow=ACCENT,
                                   glow_op=0.22, hi_op=0.35), 12, 4)
    add_frame("btn_primary_hover", frame(48, 32, 8, mix(ACCENT_HI, "#ffffff", 0.25), ACCENT_HI, ACCENT, 1.0,
                                         pad=4, glow=ACCENT, glow_op=0.55, hi_op=0.45), 12, 4)
    add_frame("btn_primary_pressed", frame(48, 32, 8, ACCENT, ACCENT_LO, ACCENT_LO, 1.0, pad=4, hi_op=0.15), 12, 4)
    # text inputs
    add_frame("input_normal", frame(48, 32, 8, mix(WELL, INK, 0.5), WELL, LINE, 1.0, pad=4, hi_op=0), 12, 4)
    add_frame("input_focus", frame(48, 32, 8, mix(WELL, INK, 0.5), WELL, ACCENT2, 0.95, pad=4, glow=ACCENT2,
                                   glow_op=0.45, hi_op=0), 12, 4)
    # list cells (ItemList)
    add_frame("cell_hover", frame(48, 48, 8, RAISED_HI, RAISED, ACCENT2, 0.8, 0.85, pad=2, hi_op=0.06), 10, 2)
    add_frame("cell_selected", frame(48, 48, 8, mix(RAISED, ACCENT, 0.24), mix(RAISED, ACCENT, 0.14), ACCENT,
                                     1.0, pad=2, hi_op=0.06), 10, 2)


def divider():
    w, h = 128, 12
    d = (f'<defs><linearGradient id="dv" x1="0" y1="0" x2="1" y2="0">'
         f'<stop offset="0" stop-color="{LINE_HI}" stop-opacity="0"/><stop offset="0.5" stop-color="{LINE_HI}"/>'
         f'<stop offset="1" stop-color="{LINE_HI}" stop-opacity="0"/></linearGradient></defs>')
    body = d + f'<rect x="0" y="5.5" width="{w}" height="1" fill="url(#dv)"/>'
    body += f'<path d="M{w / 2 - 4},6 L{w / 2},2 L{w / 2 + 4},6 L{w / 2},10 Z" fill="{ACCENT}"/>'
    return svg(w, h, body)


def knob(hover):
    s, c = 24, 12
    b = ""
    if hover:
        for k, op in ((10, 0.10), (9, 0.18), (8, 0.28)):
            b += f'<circle cx="{c}" cy="{c}" r="{k}" fill="{ACCENT2}" fill-opacity="{op}"/>'
    b += f'<circle cx="{c}" cy="{c + 0.8}" r="7" fill="#000000" fill-opacity="0.35"/>'
    d, url = vgrad("#ffffff", "#d7dee8")
    b += d + f'<circle cx="{c}" cy="{c}" r="6.5" fill="{url}" stroke="{ACCENT2 if hover else LINE_HI}" stroke-width="1"/>'
    b += f'<circle cx="{c}" cy="{c}" r="2" fill="{ACCENT2 if hover else MUTED}"/>'
    return svg(s, s, b)


def switch(on):
    w, h = 36, 20
    fill = ACCENT if on else WELL
    stroke = ACCENT_LO if on else LINE_HI
    b = f'<rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="{h / 2 - 0.5}" fill="{fill}" stroke="{stroke}"/>'
    cx = w - 10 if on else 10
    b += f'<circle cx="{cx}" cy="10.6" r="7" fill="#000000" fill-opacity="0.3"/>'
    b += f'<circle cx="{cx}" cy="10" r="7" fill="{"#ffffff" if on else DIM}"/>'
    return svg(w, h, b)


def checkbox(on):
    s = 18
    if on:
        b = f'<rect x="0.5" y="0.5" width="17" height="17" rx="4.5" fill="{ACCENT}" stroke="{ACCENT_LO}"/>'
        b += f'<path d="M4.5 9.5 L7.8 12.6 L13.5 5.8" fill="none" stroke="{INK}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
    else:
        b = f'<rect x="0.5" y="0.5" width="17" height="17" rx="4.5" fill="{WELL}" stroke="{LINE_HI}"/>'
    return svg(s, s, b)


# ------------------------------------------------------------------ icons (48 x 48 line art)
S = f'fill="none" stroke="{ICON}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"'
F = f'fill="{ICON}"'

ICONS = {
    "new": f'<path d="M14 6 H28 L36 14 V42 H14 Z" {S}/><path d="M24 22 V34 M18 28 H30" {S}/>',
    "save": f'<path d="M10 8 H34 L40 14 V40 H10 Z" {S}/><path d="M16 8 V18 H32 V8 M16 40 V28 H32 V40" {S}/>',
    "load": f'<path d="M6 14 H18 L22 18 H42 V38 H6 Z" {S}/><path d="M24 34 V24 M19 29 L24 24 L29 29" {S}/>',
    "undo": f'<path d="M14 18 H30 A10 10 0 0 1 30 38 H18" {S}/><path d="M20 11 L13 18 L20 25" {S}/>',
    "redo": f'<path d="M34 18 H18 A10 10 0 0 0 18 38 H30" {S}/><path d="M28 11 L35 18 L28 25" {S}/>',
    "file": f'<path d="M6 12 H18 L22 16 H42 V38 H6 Z" {S}/><path d="M6 22 H42" {S}/>',
    "help": f'<circle cx="24" cy="24" r="17" {S}/><path d="M18 19 A6 6 0 1 1 26 24.5 C24.5 25.5 24 26.5 24 29" {S}/><circle cx="24" cy="35" r="2.2" {F}/>',
    "hud": f'<rect x="6" y="9" width="36" height="30" rx="4" {S}/><path d="M16 9 V39 M32 9 V39" {S}/>',
    "collapse": f'<path d="M28 12 L16 24 L28 36" {S}/>',
    "expand": f'<path d="M20 12 L32 24 L20 36" {S}/>',
    "chevron_down": f'<path d="M14 19 L24 29 L34 19" {S}/>',
    "close": f'<path d="M15 15 L33 33 M33 15 L15 33" {S}/>',
    "symmetry": f'<circle cx="24" cy="24" r="6" {S}/><path d="M24 4 V12 M24 36 V44 M4 24 H12 M36 24 H44 M10 10 L15 15 M33 33 L38 38 M38 10 L33 15 M10 38 L15 33" {S}/>',
    "snap": f'<path d="M24 8 L24 24 L38 32" {S}/><path d="M24 8 A16 16 0 1 1 9.5 31" {S} stroke-dasharray="3.5 5"/><circle cx="24" cy="24" r="3" {F}/>',
    "nodes": f'<circle cx="24" cy="10" r="5" {S}/><circle cx="24" cy="38" r="5" {S}/><circle cx="10" cy="24" r="4" {S}/><circle cx="38" cy="24" r="4" {S}/><path d="M24 15 V33 M14 24 H34" {S} stroke-dasharray="2 4"/>',
    "language": f'<circle cx="24" cy="24" r="17" {S}/><path d="M7 24 H41 M24 7 C14 16 14 32 24 41 C34 32 34 16 24 7" {S}/>',
    "examples": f'<path d="M24 4 C32 12 32 26 29 34 H19 C16 26 16 12 24 4 Z" {S}/><circle cx="24" cy="18" r="3" {S}/><path d="M19 34 L13 42 L19 40 M29 34 L35 42 L29 40 M22 38 V44 M26 38 V44" {S}/>',
    "launch": f'<path d="M24 5 C31 11 33 21 31 31 H17 C15 21 17 11 24 5 Z" {S}/><circle cx="24" cy="18" r="3.2" {F}/><path d="M17 26 L11 33 V38 L17 34 M31 26 L37 33 V38 L31 34" {S}/><path d="M20.5 36 L24 44 L27.5 36" {S}/>',
    "search": f'<circle cx="21" cy="21" r="12" {S}/><path d="M30 30 L40 40" {S}/>',
    "star": f'<path d="M24 6 L29.3 17.4 L41.5 18.6 L32.3 27 L35 39.2 L24 32.9 L13 39.2 L15.7 27 L6.5 18.6 L18.7 17.4 Z" {S}/>',
    "star_fill": f'<path d="M24 6 L29.3 17.4 L41.5 18.6 L32.3 27 L35 39.2 L24 32.9 L13 39.2 L15.7 27 L6.5 18.6 L18.7 17.4 Z" {F} stroke="{ICON}" stroke-width="2" stroke-linejoin="round"/>',
    "mass": f'<path d="M14 18 H34 L40 40 H8 Z" {S}/><circle cx="24" cy="12" r="5" {S}/>',
    "thrust": f'<path d="M24 40 V10 M14 20 L24 10 L34 20" {S}/><path d="M16 44 H32" {S}/>',
    "isp": f'<path d="M24 6 C30 14 34 19 34 27 A10 10 0 0 1 14 27 C14 19 18 14 24 6 Z" {S}/><path d="M24 23 C27 27 28 29 28 31 A4 4 0 0 1 20 31 C20 29 21 27 24 23 Z" {F}/>',
    "cost": f'<circle cx="24" cy="24" r="17" {S}/><path d="M30 17 C28 15 26 14.5 24 14.5 C20 14.5 18 16.5 18 19 C18 25 30 22 30 29 C30 31.5 28 33.5 24 33.5 C21.5 33.5 19.5 32.5 18 31 M24 10.5 V14.5 M24 33.5 V37.5" {S}/>',
    "dv": f'<path d="M24 8 L40 38 H8 Z" {S}/><path d="M17 31 H31" {S}/>',
    "twr": f'<path d="M24 34 V8 M15 17 L24 8 L33 17" {S}/><path d="M10 40 H38" {S}/><path d="M15 34 H33" {S} stroke-opacity="0.55"/>',
    "burn": f'<circle cx="24" cy="26" r="15" {S}/><path d="M24 26 V17 M24 26 L30 30 M20 6 H28 M24 6 V11" {S}/>',
    "parts": f'<rect x="7" y="22" width="15" height="15" rx="2" {S}/><rect x="26" y="22" width="15" height="15" rx="2" {S}/><rect x="16.5" y="6" width="15" height="15" rx="2" {S}/>',
    "check": f'<path d="M10 25 L20 35 L38 13" {S}/>',
    "warn": f'<path d="M24 7 L42 39 H6 Z" {S}/><path d="M24 19 V28" {S}/><circle cx="24" cy="33.5" r="2.2" {F}/>',
    "danger": f'<path d="M17 6 H31 L42 17 V31 L31 42 H17 L6 31 V17 Z" {S}/><path d="M18 18 L30 30 M30 18 L18 30" {S}/>',
    "info": f'<circle cx="24" cy="24" r="17" {S}/><path d="M24 22 V34" {S}/><circle cx="24" cy="15" r="2.2" {F}/>',
    "details": f'<path d="M8 12 H40 M8 20 H30 M8 28 H40 M8 36 H30" {S}/>',
    "compact": f'<path d="M8 16 H40 M8 32 H40" {S}/>',
    "stages": f'<path d="M17 6 H31 V18 H17 Z M14 21 H34 V42 H14 Z" {S}/><path d="M14 31 H34" {S}/>',
    "crew": f'<circle cx="24" cy="20" r="12" {S}/><path d="M15 19 C15 14 19 12 24 12 C29 12 33 14 33 19 C33 23 29 24 24 24 C19 24 15 23 15 19 Z" {F} fill-opacity="0.85"/><path d="M10 42 C11 35 16 32 24 32 C32 32 37 35 38 42" {S}/>',
    "target": f'<circle cx="24" cy="24" r="16" {S}/><circle cx="24" cy="24" r="8" {S}/><circle cx="24" cy="24" r="2.5" {F}/>',
    # KSP-like marker glyphs
    "com": f'<circle cx="24" cy="24" r="16" {S}/><path d="M24 8 A16 16 0 0 1 40 24 H24 Z M24 40 A16 16 0 0 1 8 24 H24 Z" {F}/>',
    "cot": f'<circle cx="24" cy="30" r="9" {S}/><path d="M24 21 V5 M17 12 L24 5 L31 12" {S}/>',
    "col": f'<circle cx="24" cy="24" r="9" {S}/><path d="M4 24 H15 M33 24 H44 M24 15 V6" {S}/>',
    # part categories
    "cat_favorites": f'<path d="M24 6 L29.3 17.4 L41.5 18.6 L32.3 27 L35 39.2 L24 32.9 L13 39.2 L15.7 27 L6.5 18.6 L18.7 17.4 Z" {S}/>',
    "cat_command": f'<rect x="12" y="12" width="24" height="24" rx="3" {S}/><path d="M18 6 V12 M24 6 V12 M30 6 V12 M18 36 V42 M24 36 V42 M30 36 V42 M6 18 H12 M6 30 H12 M36 18 H42 M36 30 H42" {S}/><rect x="19" y="19" width="10" height="10" {F}/>',
    "cat_tank": f'<path d="M12 10 C12 5 36 5 36 10 V38 C36 43 12 43 12 38 Z" {S}/><path d="M12 10 C12 15 36 15 36 10 M12 24 H36" {S}/>',
    "cat_engine": f'<rect x="17" y="5" width="14" height="10" rx="2" {S}/><path d="M20 15 L18 22 C12 30 10 36 10 43 H38 C38 36 36 30 30 22 L28 15" {S}/>',
    "cat_structure": f'<path d="M8 40 L24 8 L40 40 Z M16 24 H32 M8 40 L32 24 M40 40 L16 24" {S}/>',
    "cat_aero": f'<path d="M24 4 C30 12 32 22 32 30 V42 H16 V30 C16 22 18 12 24 4 Z" {S}/><path d="M16 32 L8 42 H16 M32 32 L40 42 H32" {S}/>',
    "cat_control": f'<circle cx="24" cy="24" r="16" {S}/><ellipse cx="24" cy="24" rx="16" ry="6" {S}/><circle cx="24" cy="24" r="3" {F}/>',
    "cat_power": f'<path d="M27 4 L12 27 H23 L20 44 L36 19 H25 Z" {S}/>',
    "cat_comms": f'<path d="M10 14 A20 20 0 0 0 34 38 Z" {S}/><path d="M22 26 L36 12 M30 8 A12 12 0 0 1 40 18 M33 3 A18 18 0 0 1 45 15" {S}/><path d="M14 38 L10 44 H24" {S}/>',
    "cat_thermal": f'<path d="M20 30 V10 A4 4 0 0 1 28 10 V30 A8 8 0 1 1 20 30 Z" {S}/><circle cx="24" cy="36" r="3" {F}/><path d="M32 12 H38 M32 18 H36 M32 24 H38" {S}/>',
    "cat_bus": f'<path d="M24 5 L41 14 V34 L24 43 L7 34 V14 Z M7 14 L24 23 L41 14 M24 23 V43" {S}/>',
    "cat_instrument": f'<circle cx="24" cy="24" r="16" {S}/><circle cx="24" cy="24" r="8" {S}/><circle cx="24" cy="24" r="2" {F}/><path d="M24 4 V9 M24 39 V44 M4 24 H9 M39 24 H44" {S}/>',
    "cat_future": f'<path d="M14 40 L18 14 C20 8 28 8 30 14 L34 40 Z" {S}/><path d="M10 40 H38 M20 22 H28" {S}/><circle cx="24" cy="29" r="3" {S}/>',
}
ICON_PX = 24          # raster size of the line icons (drawn at 18-24 px: crisp, no mip blur)
BIG_ICONS = {"launch": 32}


def sym_icon(n):
    """Radial symmetry glyph: the vessel axis (ring) and n copies around it."""
    c, rr = 24, 15
    b = f'<circle cx="{c}" cy="{c}" r="5" fill="none" stroke="{ICON}" stroke-width="2.6"/>'
    b += f'<circle cx="{c}" cy="{c}" r="{rr}" fill="none" stroke="{ICON}" stroke-width="1.4" stroke-opacity="0.35" stroke-dasharray="2 3"/>'
    for k in range(n):
        a = -math.pi / 2 + k * 2 * math.pi / n
        x, y = c + rr * math.cos(a), c + rr * math.sin(a)
        x0, y0 = c + 7 * math.cos(a), c + 7 * math.sin(a)
        b += f'<path d="M{x0:.2f} {y0:.2f} L{x:.2f} {y:.2f}" stroke="{ICON}" stroke-width="2.2" stroke-linecap="round" stroke-opacity="0.8"/>'
        size = 5.2 if n <= 4 else 4.2
        b += f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{size}" fill="{ICON}"/>'
    return b


SYMMETRY_MODES = (1, 2, 3, 4, 6, 8)


# ------------------------------------------------------------------ MARGIN mission emblem
# Original artwork (no agency insignia): a round mission patch with a planet limb, an
# elliptical orbit crossed by a rising rocket, four-point stars and a ribbon with the
# word MARGIN drawn as geometric strokes (no <text>: the SVG rasterizer ignores fonts).
GLYPHS = {  # 30 x 40 cells, y down
    "M": "M0,40 L0,0 L15,24 L30,0 L30,40",
    "A": "M0,40 L15,0 L30,40 M6,26 L24,26",
    "R": "M0,40 L0,0 L19,0 Q30,0 30,10.5 Q30,21 19,21 L0,21 M15,21 L30,40",
    "G": "M29,9 Q26,0 15,0 Q0,0 0,20 Q0,40 15,40 Q30,40 30,26 L30,22 L17,22",
    "I": "M15,0 L15,40 M6,0 L24,0 M6,40 L24,40",
    "N": "M0,40 L0,0 L30,40 L30,0",
}


def word_path(word, x0, y0, scale=1.0, gap=13.0):
    out = []
    for i, ch in enumerate(word):
        ox = x0 + i * (30 + gap) * scale
        toks = GLYPHS[ch].replace(",", " ").split()
        res = []
        k = 0
        while k < len(toks):
            t = toks[k]
            if t[0].isalpha():
                res.append(t[0])
                t = t[1:]
                if not t:
                    k += 1
                    continue
            x = float(t)
            y = float(toks[k + 1])
            res.append(f"{ox + x * scale:.1f},{y0 + y * scale:.1f}")
            k += 2
        out.append(" ".join(res))
    return " ".join(out)


def star4(cx, cy, r, color, op=1.0):
    q = r * 0.22
    return (f'<path d="M{cx},{cy - r} L{cx + q},{cy - q} L{cx + r},{cy} L{cx + q},{cy + q} L{cx},{cy + r} '
            f'L{cx - q},{cy + q} L{cx - r},{cy} L{cx - q},{cy - q} Z" fill="{color}" opacity="{op}"/>')


def emblem():
    W = 512
    c = W / 2
    b = "<defs>"
    b += ('<radialGradient id="space" cx="0.5" cy="0.38" r="0.62">'
          '<stop offset="0" stop-color="#1f3354"/><stop offset="0.7" stop-color="#121c2e"/>'
          f'<stop offset="1" stop-color="{INK}"/></radialGradient>')
    b += ('<linearGradient id="planet" x1="0" y1="0" x2="0.35" y2="1">'
          '<stop offset="0" stop-color="#7cc4e8"/><stop offset="0.18" stop-color="#3f8fc4"/>'
          '<stop offset="0.6" stop-color="#245e93"/><stop offset="1" stop-color="#173a5e"/></linearGradient>')
    b += ('<linearGradient id="land" x1="0" y1="0" x2="0" y2="1">'
          '<stop offset="0" stop-color="#8fcf8a"/><stop offset="1" stop-color="#4f9a63"/></linearGradient>')
    b += (f'<linearGradient id="flame" x1="0" y1="0" x2="0" y2="1">'
          f'<stop offset="0" stop-color="#fff3c4"/><stop offset="0.45" stop-color="{ACCENT}"/>'
          f'<stop offset="1" stop-color="{ACCENT}" stop-opacity="0"/></linearGradient>')
    b += f'<linearGradient id="ribbon" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ACCENT_HI}"/><stop offset="1" stop-color="{ACCENT}"/></linearGradient>'
    b += f'<clipPath id="field"><circle cx="{c}" cy="{c}" r="196"/></clipPath>'
    b += "</defs>"
    b += f'<circle cx="{c}" cy="{c}" r="250" fill="{INK}"/>'
    b += f'<circle cx="{c}" cy="{c}" r="243" fill="none" stroke="{ACCENT}" stroke-width="7"/>'
    b += f'<circle cx="{c}" cy="{c}" r="229" fill="{PANEL}"/>'
    b += f'<circle cx="{c}" cy="{c}" r="229" fill="none" stroke="{P("STRUCTURE")}" stroke-width="2" stroke-dasharray="3 7" opacity="0.6"/>'
    for k in range(24):
        a = math.radians(k * 15)
        r0, r1 = (206, 218) if k % 2 == 0 else (210, 214)
        b += (f'<path d="M{c + r0 * math.sin(a):.1f},{c - r0 * math.cos(a):.1f} L{c + r1 * math.sin(a):.1f},'
              f'{c - r1 * math.cos(a):.1f}" stroke="{ACCENT2}" stroke-width="3" stroke-linecap="round" opacity="0.85"/>')
    b += '<g clip-path="url(#field)">'
    b += f'<rect x="0" y="0" width="{W}" height="{W}" fill="url(#space)"/>'
    for (x, y, r, op) in ((150, 120, 3, 0.9), (360, 108, 2.2, 0.8), (392, 200, 2.6, 0.7), (118, 228, 2, 0.6),
                          (300, 82, 1.8, 0.7), (205, 172, 1.6, 0.6), (420, 260, 1.6, 0.5), (96, 170, 1.6, 0.5)):
        b += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{TEXT}" opacity="{op}"/>'
    b += star4(166, 150, 16, TEXT)
    b += star4(372, 152, 11, TEXT, 0.9)
    b += star4(328, 98, 7, ACCENT2)
    b += f'<circle cx="{c}" cy="{c + 330}" r="250" fill="url(#planet)"/>'
    b += f'<circle cx="{c}" cy="{c + 330}" r="250" fill="none" stroke="#bfe9ff" stroke-width="6" opacity="0.55"/>'
    b += '<path d="M150,372 h24 v-8 h24 v-8 h40 v8 h16 v10 h-20 v12 h-30 v-6 h-26 v8 h-28 Z" fill="url(#land)" opacity="0.95"/>'
    b += '<path d="M318,356 h30 v-6 h22 v10 h18 v14 h-34 v-8 h-36 Z" fill="url(#land)" opacity="0.9"/>'
    rot = -16
    b += (f'<ellipse cx="{c}" cy="{c + 6}" rx="178" ry="56" fill="none" stroke="{TEXT}" stroke-width="3" '
          f'opacity="0.45" transform="rotate({rot} {c} {c + 6})"/>')
    b += (f'<g transform="translate({c} {c - 6}) rotate(14)">'
          f'<path d="M-9,64 Q0,118 9,64 Z" fill="url(#flame)"/>'
          f'<path d="M-15,58 L-15,-38 Q-15,-80 0,-104 Q15,-80 15,-38 L15,58 Z" fill="{TEXT}"/>'
          f'<path d="M-15,-38 Q-15,-80 0,-104 Q15,-80 15,-38 Z" fill="{P("STRUCTURE")}"/>'
          f'<rect x="-15" y="-30" width="30" height="9" fill="{ACCENT}"/>'
          f'<rect x="-15" y="34" width="30" height="7" fill="{INK}" opacity="0.85"/>'
          f'<circle cx="0" cy="-52" r="6" fill="{ACCENT2}" stroke="{INK}" stroke-width="2"/>'
          f'<path d="M-15,30 L-32,62 L-32,72 L-15,58 Z M15,30 L32,62 L32,72 L15,58 Z" fill="{ACCENT}"/>'
          f'<path d="M-6,58 L-9,68 L9,68 L6,58 Z" fill="{P("GUNMETAL")}"/>'
          f'</g>')
    b += (f'<path d="M{c - 178},{c + 6} A178,56 0 0 0 {c + 178},{c + 6}" fill="none" stroke="{TEXT}" '
          f'stroke-width="6" stroke-linecap="round" transform="rotate({rot} {c} {c + 6})"/>')
    b += (f'<circle cx="{c + 178}" cy="{c + 6}" r="9" fill="{ACCENT2}" stroke="{TEXT}" stroke-width="3" '
          f'transform="rotate({rot} {c} {c + 6})"/>')
    b += "</g>"
    y0, y1 = 388, 452
    b += f'<path d="M30,{y0 + 10} L70,{y0 + 4} L70,{y1 + 6} L30,{y1 + 10} L48,{(y0 + y1) / 2 + 10} Z" fill="{ACCENT}" opacity="0.8"/>'
    b += f'<path d="M{W - 30},{y0 + 10} L{W - 70},{y0 + 4} L{W - 70},{y1 + 6} L{W - 30},{y1 + 10} L{W - 48},{(y0 + y1) / 2 + 10} Z" fill="{ACCENT}" opacity="0.8"/>'
    b += (f'<path d="M62,{y0} Q{c},{y0 - 22} {W - 62},{y0} L{W - 62},{y1} Q{c},{y1 - 22} 62,{y1} Z" '
          f'fill="url(#ribbon)" stroke="{INK}" stroke-width="3"/>')
    word_w = 6 * 30 + 5 * 13
    sc = 0.92
    b += (f'<path d="{word_path("MARGIN", c - word_w * sc / 2, y0 - 2, sc)}" fill="none" stroke="{INK}" '
          f'stroke-width="7.5" stroke-linecap="square" stroke-linejoin="miter"/>')
    return svg(W, W, b)


# ================================================================== Godot theme writer
def gcol(hx, a=1.0):
    r, g, b = hexrgb(hx)
    return f"Color({r:.4g}, {g:.4g}, {b:.4g}, {a:.4g})"


class ThemeWriter:
    def __init__(self):
        self.ext = []      # (id, type, path)
        self.subs = []     # (id, type, [(k, v)])
        self.entries = []  # (key, value)

    def ext_tex(self, name):
        rid = "kit_" + name
        if not any(e[0] == rid for e in self.ext):
            self.ext.append((rid, "Texture2D", f"res://ui/kit/{name}.svg"))
        return f'ExtResource("{rid}")'

    def sub(self, rid, typ, props):
        self.subs.append((rid, typ, props))
        return f'SubResource("{rid}")'

    def set(self, key, value):
        self.entries.append((key, value))

    @staticmethod
    def _margins(props, m, prefix="content_margin_"):
        l, t, r, b = m if len(m) == 4 else (m[0], m[1], m[0], m[1])
        props += [(prefix + "left", f"{float(l)}"), (prefix + "top", f"{float(t)}"),
                  (prefix + "right", f"{float(r)}"), (prefix + "bottom", f"{float(b)}")]

    def tex(self, rid, frame_name, content):
        _, margin, expand = FRAMES[frame_name]
        props = []
        self._margins(props, content)
        props.append(("texture", self.ext_tex(frame_name)))
        self._margins(props, (margin, margin), "texture_margin_")
        if expand:
            self._margins(props, (expand, expand), "expand_margin_")
        return self.sub(rid, "StyleBoxTexture", props)

    def flat(self, rid, bg, alpha=1.0, content=(0, 0), radius=0, border=None, border_alpha=1.0, bw=1,
             shadow=None, shadow_size=0, shadow_offset=(0, 0), expand=None, aa=True):
        props = []
        self._margins(props, content)
        props.append(("bg_color", gcol(bg, alpha)))
        if border:
            for s in ("left", "top", "right", "bottom"):
                props.append((f"border_width_{s}", str(bw)))
            props.append(("border_color", gcol(border, border_alpha)))
        if radius:
            for s in ("top_left", "top_right", "bottom_right", "bottom_left"):
                props.append((f"corner_radius_{s}", str(radius)))
            props.append(("corner_detail", "8"))
        if expand:
            self._margins(props, expand, "expand_margin_")
        if shadow:
            props.append(("shadow_color", gcol(shadow[0], shadow[1])))
            props.append(("shadow_size", str(shadow_size)))
            props.append(("shadow_offset", f"Vector2({shadow_offset[0]}, {shadow_offset[1]})"))
        if not aa:
            props.append(("anti_aliasing", "false"))
        return self.sub(rid, "StyleBoxFlat", props)

    def empty(self, rid, content=(0, 0)):
        props = []
        self._margins(props, content)
        return self.sub(rid, "StyleBoxEmpty", props)

    def line(self, rid, color, alpha=1.0, vertical=False, thickness=1):
        props = [("color", gcol(color, alpha)), ("thickness", str(thickness))]
        if vertical:
            props.append(("vertical", "true"))
        return self.sub(rid, "StyleBoxLine", props)

    def write(self, path):
        out = [f'[gd_resource type="Theme" load_steps={len(self.ext) + len(self.subs) + 1} format=3]', ""]
        for rid, typ, p in self.ext:
            out.append(f'[ext_resource type="{typ}" path="{p}" id="{rid}"]')
        out.append("")
        for rid, typ, props in self.subs:
            out.append(f'[sub_resource type="{typ}" id="{rid}"]')
            for k, v in props:
                out.append(f"{k} = {v}")
            out.append("")
        out.append("[resource]")
        for k, v in self.entries:
            out.append(f"{k} = {v}")
        path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def build_theme():
    t = ThemeWriter()
    # fonts
    f_body = t.sub("font_body", "SystemFont", [("font_names", 'PackedStringArray("Segoe UI", "Arial", "Noto Sans")'),
                                               ("subpixel_positioning", "0")])
    f_semi = t.sub("font_semibold", "SystemFont", [("font_names", 'PackedStringArray("Segoe UI Semibold", "Segoe UI", "Arial")'),
                                                   ("font_weight", "600")])
    f_title = t.sub("font_title", "SystemFont", [("font_names", 'PackedStringArray("Bahnschrift", "Segoe UI", "Arial")'),
                                                 ("font_weight", "600")])
    f_caps = t.sub("font_caps", "FontVariation", [("base_font", f_title), ("spacing_glyph", "1")])
    f_mono = t.sub("font_mono", "SystemFont", [("font_names", 'PackedStringArray("Cascadia Mono", "Consolas", "Courier New")')])

    C = gcol
    t.set("default_font", f_body)
    t.set("default_font_size", "14")

    # ---------------------------------------------------------------- containers / panels
    panel = t.tex("tx_panel", "panel_frame", (16, 14))
    t.set("PanelContainer/styles/panel", panel)
    t.set("Panel/styles/panel", panel)
    t.set("TopBarPanel/base_type", '&"PanelContainer"')
    t.set("TopBarPanel/styles/panel", t.tex("tx_topbar", "topbar_frame", (14, 8, 10, 8)))
    t.set("ReadoutPanel/base_type", '&"PanelContainer"')
    t.set("ReadoutPanel/styles/panel", t.tex("tx_readout", "readout_frame", (20, 10)))
    t.set("CardPanel/base_type", '&"PanelContainer"')
    t.set("CardPanel/styles/panel", t.tex("tx_card", "card_frame", (14, 9, 12, 9)))
    t.set("CardFlat/base_type", '&"PanelContainer"')
    t.set("CardFlat/styles/panel", t.tex("tx_card_plain", "card_plain", (12, 9)))
    t.set("CardHover/base_type", '&"PanelContainer"')
    t.set("CardHover/styles/panel", t.tex("tx_card_hover", "card_hover", (12, 9)))
    t.set("SubPanel/base_type", '&"PanelContainer"')
    t.set("SubPanel/styles/panel", t.flat("sub_panel", WELL, 0.72, (12, 10), 10, LINE, 1.0))
    t.set("ToolGroup/base_type", '&"PanelContainer"')
    t.set("ToolGroup/styles/panel", t.flat("tool_group", WELL, 0.8, (3, 3), 10, LINE, 1.0))
    float_panel = t.flat("float_panel", PANEL, 0.97, (14, 12), 12, LINE_HI, 0.9, shadow=("#000000", 0.5),
                         shadow_size=18, shadow_offset=(0, 4))
    t.set("FloatPanel/base_type", '&"PanelContainer"')
    t.set("FloatPanel/styles/panel", float_panel)
    t.set("PopupPanel/styles/panel", float_panel)
    t.set("ToastPanel/base_type", '&"PanelContainer"')
    t.set("ToastPanel/styles/panel", t.flat("toast", INK, 0.94, (18, 8), 18, ACCENT, 0.55,
                                            shadow=("#000000", 0.45), shadow_size=12, shadow_offset=(0, 3)))
    t.set("BarTrack/base_type", '&"PanelContainer"')
    t.set("BarTrack/styles/panel", t.flat("bar_track", INK, 0.9, (1, 1), 4, LINE, 1.0))
    # chips / badges (pills): neutral + tones
    t.set("Chip/base_type", '&"PanelContainer"')
    t.set("Chip/styles/panel", t.flat("chip", RAISED, 1.0, (8, 3), 11, LINE, 1.0))
    for tone, col in (("Ok", P("SUCCESS")), ("Warn", P("WARNING")), ("Danger", P("DANGER")),
                      ("Info", ACCENT2), ("Accent", ACCENT)):
        t.set(f"Chip{tone}/base_type", '&"Chip"')
        t.set(f"Chip{tone}/styles/panel", t.flat(f"chip_{tone.lower()}", mix(PANEL, col, 0.16), 1.0, (8, 3), 11,
                                                 col, 0.5))

    # ---------------------------------------------------------------- labels
    t.set("Label/colors/font_color", C(TEXT))
    t.set("Label/colors/font_shadow_color", C("#000000", 0))
    for name, base, color, font, size in (
        ("DimLabel", "Label", DIM, None, 13),
        ("CaptionLabel", "Label", DIM, f_caps, 11),
        ("SectionLabel", "Label", ACCENT2, f_caps, 12),
        ("TitleLabel", "Label", TEXT, f_title, 19),
        ("CardTitle", "Label", TEXT, f_semi, 15),
        ("LogoLabel", "Label", ACCENT, f_title, 24),
        ("ValueLabel", "Label", TEXT, f_title, 18),
        ("BigValueLabel", "Label", TEXT, f_title, 24),
        ("AccentLabel", "Label", ACCENT_HI, f_title, 15),
        ("MonoLabel", "Label", None, f_mono, None),
    ):
        t.set(f"{name}/base_type", f'&"{base}"')
        if color:
            t.set(f"{name}/colors/font_color", C(color))
        if font:
            t.set(f"{name}/fonts/font", font)
        if size:
            t.set(f"{name}/font_sizes/font_size", str(size))
    t.set("KeyCap/base_type", '&"Label"')
    t.set("KeyCap/colors/font_color", C(TEXT))
    t.set("KeyCap/fonts/font", f_mono)
    t.set("KeyCap/font_sizes/font_size", "12")
    t.set("KeyCap/styles/normal", t.flat("keycap", RAISED, 1.0, (8, 3), 5, LINE_HI, 1.0))
    t.set("RichTextLabel/colors/default_color", C(TEXT))
    t.set("RichTextLabel/fonts/mono_font", f_mono)
    t.set("RichTextLabel/fonts/bold_font", f_semi)

    # ---------------------------------------------------------------- buttons
    focus = t.empty("focus_none")
    b_normal = t.tex("tx_btn_normal", "btn_normal", (12, 6))
    b_hover = t.tex("tx_btn_hover", "btn_hover", (12, 6))
    b_pressed = t.tex("tx_btn_pressed", "btn_pressed", (12, 6))
    b_pressed_h = t.tex("tx_btn_pressed_hover", "btn_pressed_hover", (12, 6))
    b_disabled = t.tex("tx_btn_disabled", "btn_disabled", (12, 6))
    flat_n = t.empty("flat_normal", (10, 6))
    flat_h = t.tex("tx_flat_hover", "flat_hover", (10, 6))
    flat_p = t.flat("flat_pressed", mix(WELL, ACCENT, 0.2), 1.0, (10, 6), 7, ACCENT, 0.7)
    flat_ph = t.flat("flat_pressed_hover", mix(WELL, ACCENT, 0.28), 1.0, (10, 6), 7, ACCENT_HI, 0.85)

    def button_colors(prefix, normal, hover, pressed, disabled=MUTED, icon_normal=None, icon_hover=None,
                      icon_pressed=None):
        t.set(f"{prefix}/colors/font_color", C(normal))
        t.set(f"{prefix}/colors/font_hover_color", C(hover))
        t.set(f"{prefix}/colors/font_pressed_color", C(pressed))
        t.set(f"{prefix}/colors/font_hover_pressed_color", C(pressed))
        t.set(f"{prefix}/colors/font_focus_color", C(normal))
        t.set(f"{prefix}/colors/font_disabled_color", C(disabled))
        t.set(f"{prefix}/colors/icon_normal_color", C(icon_normal or normal))
        t.set(f"{prefix}/colors/icon_hover_color", C(icon_hover or hover))
        t.set(f"{prefix}/colors/icon_pressed_color", C(icon_pressed or pressed))
        t.set(f"{prefix}/colors/icon_hover_pressed_color", C(icon_pressed or pressed))
        t.set(f"{prefix}/colors/icon_focus_color", C(icon_normal or normal))
        t.set(f"{prefix}/colors/icon_disabled_color", C(disabled))

    def button_styles(prefix, n, h, p, ph, d):
        t.set(f"{prefix}/styles/normal", n)
        t.set(f"{prefix}/styles/hover", h)
        t.set(f"{prefix}/styles/pressed", p)
        t.set(f"{prefix}/styles/hover_pressed", ph)
        t.set(f"{prefix}/styles/disabled", d)
        t.set(f"{prefix}/styles/focus", focus)

    button_styles("Button", b_normal, b_hover, b_pressed, b_pressed_h, b_disabled)
    button_colors("Button", TEXT, "#ffffff", ACCENT_HI, icon_hover="#ffffff", icon_pressed=ACCENT)
    t.set("Button/constants/h_separation", "7")
    t.set("Button/constants/icon_max_width", "20")
    t.set("Button/font_sizes/font_size", "14")

    t.set("FlatButton/base_type", '&"Button"')
    button_styles("FlatButton", flat_n, flat_h, flat_p, flat_ph, flat_n)
    button_colors("FlatButton", TEXT, "#ffffff", ACCENT_HI, icon_normal=mix(TEXT, DIM, 0.35),
                  icon_hover="#ffffff", icon_pressed=ACCENT)

    t.set("PrimaryButton/base_type", '&"Button"')
    button_styles("PrimaryButton", t.tex("tx_primary", "btn_primary", (16, 6)),
                  t.tex("tx_primary_hover", "btn_primary_hover", (16, 6)),
                  t.tex("tx_primary_pressed", "btn_primary_pressed", (16, 6)),
                  t.tex("tx_primary_pressed_h", "btn_primary_pressed", (16, 6)), b_disabled)
    button_colors("PrimaryButton", INK, INK, INK)
    t.set("PrimaryButton/fonts/font", f_title)
    t.set("PrimaryButton/font_sizes/font_size", "15")

    seg_n = t.empty("seg_normal", (10, 5))
    t.set("SegmentButton/base_type", '&"Button"')
    button_styles("SegmentButton", seg_n, flat_h, flat_p, flat_ph, seg_n)
    button_colors("SegmentButton", DIM, TEXT, ACCENT_HI, icon_normal=DIM, icon_hover=TEXT, icon_pressed=ACCENT)
    t.set("SegmentButton/font_sizes/font_size", "13")
    t.set("SegmentButton/fonts/font", f_semi)

    t.set("SymButton/base_type", '&"SegmentButton"')
    t.set("SymButton/constants/icon_max_width", "30")
    t.set("SymButton/constants/h_separation", "2")

    t.set("IconToggle/base_type", '&"Button"')
    cat_n = t.empty("cat_normal", (6, 6))
    button_styles("IconToggle", cat_n, flat_h, flat_p, flat_ph, cat_n)
    button_colors("IconToggle", DIM, TEXT, ACCENT, icon_normal=mix(DIM, TEXT, 0.3), icon_hover="#ffffff",
                  icon_pressed=ACCENT)
    t.set("IconToggle/constants/icon_max_width", "20")

    t.set("PartCard/base_type", '&"Button"')
    button_styles("PartCard", t.tex("tx_part", "card_plain", (6, 6, 6, 5)),
                  t.tex("tx_part_hover", "card_hover", (6, 6, 6, 5)),
                  t.tex("tx_part_pressed", "card_selected", (6, 6, 6, 5)),
                  t.tex("tx_part_pressed_h", "card_selected", (6, 6, 6, 5)),
                  t.tex("tx_part_disabled", "card_plain", (6, 6, 6, 5)))
    button_colors("PartCard", DIM, TEXT, ACCENT_HI, icon_normal="#ffffff", icon_hover="#ffffff",
                  icon_pressed="#ffffff")
    t.set("PartCard/font_sizes/font_size", "11")
    t.set("PartCard/constants/icon_max_width", "52")
    t.set("PartCard/constants/h_separation", "2")
    t.set("PartCard/constants/line_spacing", "-2")

    t.set("MarkerToggle/base_type", '&"Button"')
    mk_n = t.flat("marker_off", WELL, 0.6, (10, 5), 8, LINE, 0.8)
    button_styles("MarkerToggle", mk_n, flat_h, b_normal, b_hover, mk_n)
    button_colors("MarkerToggle", MUTED, DIM, TEXT)
    t.set("MarkerToggle/font_sizes/font_size", "13")
    t.set("MarkerToggle/fonts/font", f_semi)

    t.set("MenuButton/styles/normal", b_normal)
    t.set("MenuButton/styles/hover", b_hover)
    t.set("MenuButton/styles/pressed", b_pressed)
    t.set("MenuButton/styles/focus", focus)
    button_colors("MenuButton", TEXT, "#ffffff", ACCENT_HI)

    t.set("OptionButton/styles/normal", b_normal)
    t.set("OptionButton/styles/hover", b_hover)
    t.set("OptionButton/styles/pressed", b_pressed)
    t.set("OptionButton/styles/hover_pressed", b_pressed_h)
    t.set("OptionButton/styles/disabled", b_disabled)
    t.set("OptionButton/styles/focus", focus)
    button_colors("OptionButton", TEXT, "#ffffff", ACCENT_HI)
    t.set("OptionButton/icons/arrow", t.ext_tex("icon_chevron_down"))
    t.set("OptionButton/constants/arrow_margin", "10")

    for typ in ("CheckButton", "CheckBox"):
        e = t.empty(f"{typ.lower()}_empty", (2, 4))
        for s in ("normal", "hover", "pressed", "hover_pressed", "disabled", "focus"):
            t.set(f"{typ}/styles/{s}", e)
        t.set(f"{typ}/colors/font_color", C(DIM))
        t.set(f"{typ}/colors/font_hover_color", C(TEXT))
        t.set(f"{typ}/colors/font_pressed_color", C(TEXT))
        t.set(f"{typ}/colors/font_hover_pressed_color", C("#ffffff"))
        t.set(f"{typ}/colors/font_focus_color", C(DIM))
        t.set(f"{typ}/constants/h_separation", "10")
    t.set("CheckButton/icons/checked", t.ext_tex("switch_on"))
    t.set("CheckButton/icons/unchecked", t.ext_tex("switch_off"))
    t.set("CheckButton/icons/checked_mirrored", t.ext_tex("switch_on"))
    t.set("CheckButton/icons/unchecked_mirrored", t.ext_tex("switch_off"))
    t.set("CheckBox/icons/checked", t.ext_tex("check_on"))
    t.set("CheckBox/icons/unchecked", t.ext_tex("check_off"))

    # ---------------------------------------------------------------- inputs, lists, menus
    t.set("LineEdit/styles/normal", t.tex("tx_input", "input_normal", (12, 6)))
    t.set("LineEdit/styles/focus", t.tex("tx_input_focus", "input_focus", (12, 6)))
    t.set("LineEdit/styles/read_only", t.tex("tx_input_ro", "input_normal", (12, 6)))
    t.set("LineEdit/colors/font_color", C(TEXT))
    t.set("LineEdit/colors/font_placeholder_color", C(MUTED))
    t.set("LineEdit/colors/caret_color", C(ACCENT))
    t.set("LineEdit/colors/selection_color", C(ACCENT2, 0.35))
    t.set("LineEdit/colors/clear_button_color", C(DIM))
    t.set("LineEdit/colors/clear_button_color_pressed", C(ACCENT))
    t.set("LineEdit/icons/clear", t.ext_tex("icon_close_small"))
    t.set("LineEdit/font_sizes/font_size", "14")

    t.set("ItemList/colors/font_color", C(DIM))
    t.set("ItemList/colors/font_hovered_color", C(TEXT))
    t.set("ItemList/colors/font_selected_color", C(ACCENT_HI))
    t.set("ItemList/constants/h_separation", "6")
    t.set("ItemList/constants/v_separation", "6")
    t.set("ItemList/constants/icon_margin", "4")
    t.set("ItemList/font_sizes/font_size", "11")
    t.set("ItemList/styles/panel", t.flat("list_bg", WELL, 0.6, (6, 6), 10, LINE, 1.0))
    t.set("ItemList/styles/focus", focus)
    cell_h = t.tex("tx_cell_hover", "cell_hover", (4, 4))
    cell_s = t.tex("tx_cell_selected", "cell_selected", (4, 4))
    for s in ("hovered",):
        t.set(f"ItemList/styles/{s}", cell_h)
    for s in ("selected", "selected_focus", "hovered_selected", "hovered_selected_focus"):
        t.set(f"ItemList/styles/{s}", cell_s)

    t.set("PopupMenu/styles/panel", t.flat("popup", PANEL, 0.98, (6, 8), 12, LINE_HI, 0.9,
                                           shadow=("#000000", 0.5), shadow_size=16, shadow_offset=(0, 4)))
    t.set("PopupMenu/styles/hover", t.flat("popup_hover", mix(PANEL, ACCENT, 0.18), 1.0, (8, 4), 7, ACCENT, 0.45))
    t.set("PopupMenu/styles/separator", t.line("popup_sep", LINE))
    t.set("PopupMenu/styles/labeled_separator_left", t.line("popup_sep_l", LINE))
    t.set("PopupMenu/styles/labeled_separator_right", t.line("popup_sep_r", LINE))
    t.set("PopupMenu/colors/font_color", C(TEXT))
    t.set("PopupMenu/colors/font_hover_color", C(ACCENT_HI))
    t.set("PopupMenu/colors/font_separator_color", C(ACCENT2))
    t.set("PopupMenu/colors/font_disabled_color", C(MUTED))
    t.set("PopupMenu/fonts/font_separator", f_caps)
    t.set("PopupMenu/font_sizes/font_separator_size", "11")
    t.set("PopupMenu/constants/v_separation", "10")
    t.set("PopupMenu/constants/h_separation", "10")
    t.set("PopupMenu/constants/item_start_padding", "10")
    t.set("PopupMenu/constants/item_end_padding", "14")
    t.set("PopupMenu/constants/icon_max_width", "18")

    t.set("TooltipPanel/styles/panel", t.flat("tooltip", INK, 0.97, (10, 7), 8, LINE_HI, 1.0,
                                              shadow=("#000000", 0.4), shadow_size=8, shadow_offset=(0, 2)))
    t.set("TooltipLabel/colors/font_color", C(TEXT))
    t.set("TooltipLabel/font_sizes/font_size", "13")

    # ---------------------------------------------------------------- bars, sliders, scrollbars
    t.set("ProgressBar/styles/background", t.flat("bar_bg", INK, 0.85, (0, 0), 4, LINE, 1.0))
    t.set("ProgressBar/styles/fill", t.flat("bar_fill", ACCENT2, 1.0, (0, 0), 4))
    t.set("ProgressBar/colors/font_color", C("#000000", 0))
    t.set("HSlider/styles/slider", t.flat("slider_h", INK, 0.9, (0, 2), 3, LINE, 1.0))
    t.set("VSlider/styles/slider", t.flat("slider_v", INK, 0.9, (2, 0), 3, LINE, 1.0))
    ga = t.flat("slider_fill", ACCENT2, 0.55, (0, 0), 3)
    gah = t.flat("slider_fill_hi", ACCENT2, 0.85, (0, 0), 3)
    for typ in ("HSlider", "VSlider"):
        t.set(f"{typ}/styles/grabber_area", ga)
        t.set(f"{typ}/styles/grabber_area_highlight", gah)
        t.set(f"{typ}/icons/grabber", t.ext_tex("knob"))
        t.set(f"{typ}/icons/grabber_highlight", t.ext_tex("knob_hover"))
        t.set(f"{typ}/icons/grabber_disabled", t.ext_tex("knob"))
    t.set("VScrollBar/styles/scroll", t.empty("vscroll_bg", (3, 2)))
    t.set("HScrollBar/styles/scroll", t.empty("hscroll_bg", (2, 3)))
    g = t.flat("scroll_grabber", DIM, 0.3, (0, 0), 3)
    gh = t.flat("scroll_grabber_hi", DIM, 0.55, (0, 0), 3)
    gp = t.flat("scroll_grabber_p", ACCENT2, 0.8, (0, 0), 3)
    for typ in ("VScrollBar", "HScrollBar"):
        t.set(f"{typ}/styles/grabber", g)
        t.set(f"{typ}/styles/grabber_highlight", gh)
        t.set(f"{typ}/styles/grabber_pressed", gp)
    t.set("HSeparator/styles/separator", t.line("sep_h", LINE))
    t.set("HSeparator/constants/separation", "8")
    t.set("VSeparator/styles/separator", t.line("sep_v", LINE, vertical=True))
    t.set("VSeparator/constants/separation", "10")
    t.write(ROOT / "ui" / "margin_theme.tres")
    return t


# ================================================================== palette outputs
def palette_gd():
    lines = ["class_name MarginPalette",
             "extends RefCounted",
             "## MARGIN palette 2.0 (generated by tools/make_ui_kit.py: edit PALETTE there).",
             "## Rules and swatches: docs/art/palette.md. MARK_* are reserved for the KSP-style",
             "## CoM / CoT / CoL markers and their legend; nothing else may use them.",
             ""]
    for group, table in (("palette tokens", PALETTE), ("reserved marker colours", MARKERS),
                         ("light colours", LIGHTS)):
        lines.append(f"# {group}")
        for name, (hx, role) in table.items():
            r, g, b = hexrgb(hx)
            lines.append(f"## {role}")
            lines.append(f"const {name} := Color({r:.4f}, {g:.4f}, {b:.4f})  # {hx}")
        lines.append("")
    lines.append("## Data series in order (stage colours, chart series).")
    lines.append("const DATA: Array[Color] = [DATA_1, DATA_2, DATA_3, DATA_4, DATA_5, DATA_6]")
    lines.append("")
    lines.append("## Token name -> Color, in display order (for tooling / debug swatches).")
    lines.append("const ALL := {")
    for name in list(PALETTE) + list(MARKERS) + list(LIGHTS):
        lines.append(f'\t"{name}": {name},')
    lines.append("}")
    lines.append("")
    lines.append("")
    lines.append("## Series colour for index i (wraps).")
    lines.append("static func data(i: int) -> Color:")
    lines.append("\treturn DATA[posmod(i, DATA.size())]")
    return "\n".join(lines) + "\n"


def swatches_svg():
    cols = 6
    w, h = 150, 112
    rows = []
    for title, names in GROUPS:
        rows.append(("title", title))
        for i in range(0, len(names), cols):
            rows.append(("row", names[i:i + cols]))
    H = 20 + sum(28 if k == "title" else h for k, _ in rows)
    W = cols * w + 20
    b = f'<rect width="{W}" height="{H}" fill="{INK}"/>'
    y = 10
    for kind, val in rows:
        if kind == "title":
            b += (f'<text x="16" y="{y + 20}" font-family="Bahnschrift, Segoe UI, Arial" font-size="14" '
                  f'font-weight="600" fill="{ACCENT2}">{val}</text>')
            y += 28
            continue
        for i, name in enumerate(val):
            hx = P(name)
            x = 10 + i * w
            b += f'<rect x="{x + 6}" y="{y + 4}" width="{w - 12}" height="60" rx="8" fill="{hx}" stroke="{LINE}"/>'
            b += f'<text x="{x + 8}" y="{y + 84}" font-family="Segoe UI, Arial" font-size="13" font-weight="600" fill="{TEXT}">{name}</text>'
            b += f'<text x="{x + 8}" y="{y + 101}" font-family="Consolas, monospace" font-size="12" fill="{DIM}">{hx}</text>'
        y += h
    return svg(W, H, b)


def palette_md():
    rows = []
    for title, names in GROUPS:
        rows.append(f"| **{title}** | | | |")
        for n in names:
            hx = P(n)
            role = (PALETTE.get(n) or MARKERS.get(n) or LIGHTS[n])[1]
            cr = contrast(hx, PANEL)
            rows.append(f"| `{n}` | `{hx}` | {cr:.1f}:1 | {role} |")
    table = "\n".join(rows)
    checks = []
    for fg in ("TEXT", "TEXT_DIM", "TEXT_MUTED", "ACCENT", "ACCENT_2", "SUCCESS", "WARNING", "DANGER"):
        checks.append(f"| `{fg}` | {contrast(P(fg), PANEL):.1f}:1 | {contrast(P(fg), RAISED):.1f}:1 | "
                      f"{contrast(P(fg), INK):.1f}:1 |")
    checks = "\n".join(checks)
    return MD_TEMPLATE.replace("{TABLE}", table).replace("{CHECKS}", checks).replace(
        "{INK_ON_ACCENT}", f"{contrast(INK, ACCENT):.1f}")


MD_TEMPLATE = """# MARGIN — paleta 2.0 e direção de arte / palette 2.0 and art direction

> Gerado por / generated by `tools/make_ui_kit.py` — não edite à mão / do not edit by hand.

Fonte única: `PALETTE`, `MARKERS` e `LIGHTS` em [`tools/make_ui_kit.py`](../../tools/make_ui_kit.py).
O script gera o UI kit (`ui/kit/*.svg`: molduras 9-patch, ícones, emblema), o **tema Godot**
[`ui/margin_theme.tres`](../../ui/margin_theme.tres) usado por todos os HUDs (hangar, mapa,
superfícies, voo), [`ui/palette.gd`](../../ui/palette.gd) (`MarginPalette.ACCENT`, …), esta
página e [`palette_swatches.svg`](palette_swatches.svg). `tools/build_vab_scene.py` importa a
mesma tabela para os materiais e luzes do hangar. Para mudar uma cor: edite a tabela, rode
`python tools/make_ui_kit.py` e reimporte no Godot.

Single source: `PALETTE` / `MARKERS` / `LIGHTS` in `tools/make_ui_kit.py`; it writes the kit,
the Godot theme, `MarginPalette`, this page and the swatch sheet.

![swatches](palette_swatches.svg)

## Tokens

Contraste medido sobre `PANEL` / contrast measured against `PANEL`.

| Token | Hex | vs PANEL | Papel / role |
|---|---|---|---|
{TABLE}

### Contraste de texto / text contrast (WCAG)

| Texto | sobre PANEL | sobre RAISED | sobre INK |
|---|---|---|---|
{CHECKS}

`INK` sobre `ACCENT` (texto do botão primário / primary button text): {INK_ON_ACCENT}:1.

## Hierarquia / hierarchy

1. **Superfícies** do mais fundo ao mais alto: `INK` (fundo) → `WELL` (campos, trilhos,
   grupos de ferramentas) → `PANEL` (painéis, gradiente até `PANEL_HI`) → `RAISED` (cartões,
   botões) → `RAISED_HI` (hover). Cada nível é ~4 % mais claro. / Surfaces step up ~4 % in
   lightness per level.
2. **Contornos** de 1 px nítidos: `LINE` (normal) e `LINE_HI` (hover / destaque). Raio
   consistente: 12 px painéis, 9 px cartões, 8 px botões e campos, 11 px pílulas.
3. **Texto**: `TEXT` (principal), `TEXT_DIM` (secundário, legendas), `TEXT_MUTED`
   (desativado, placeholders). Nunca texto `TEXT_MUTED` com informação essencial.
4. **Um acento por vez.** `ACCENT` (Signal Orange) = marca, seleção e a ação principal
   (**Lançar**). `ACCENT_2` (Mission Blue) = informação, foco, progresso, rótulos de seção. O
   Mission Blue foi deslocado para um azul-anil (`#6aa9ff`) para ficar distinto do ciano do CoL.
   / One accent at a time; Mission Blue is now an azure, clearly apart from the CoL cyan.
5. **Status**: `SUCCESS` / `WARNING` / `DANGER`, sempre acompanhados de ícone (✓ ⚠ ⛔) para
   não depender só da cor. Chips tonais: fundo = 16 % da cor sobre `PANEL`, borda 50 %.
6. **Dados**: `DATA_1…6` para séries de gráficos e cores de estágio (o mesmo estágio tem a
   mesma cor no cartão e na barra de Δv). Evitam amarelo, magenta e ciano puros.
7. **Marcadores KSP reservados**: CoM amarelo `MARK_COM`, CoT magenta `MARK_COT`, CoL ciano
   `MARK_COL` (`src/hangar/markers.gd`, materiais em `scenes/hangar.tscn`). Só os marcadores
   e sua legenda usam essas cores. / Marker colours are reserved.
8. **Brilho**: hover = halo `ACCENT_2` de 4 px; foco de campo = halo `ACCENT_2`; ação primária
   = halo `ACCENT`. Painéis têm sombra suave e um traço de luz de 1 px no topo.

## Materiais do mundo / world materials

- fechamento (paredes, teto, painéis de porta) → `STRUCTURE`
- estrutura primária (colunas, vigas, treliças, torres, garras do pad) → `METAL`
- piso de circulação e máquinas (grades, decks, base do pad, rodapé de 3,5 m) → `GUNMETAL`
- segurança (corrimãos, ponte rolante, faixas no piso, batentes da porta) → `HAZARD` (+ `INK` nas listras)
- marca (emblema, faixas da missão, pontas dos braços de acesso) → `ACCENT` / `ACCENT_2`
- luz → `LAMP_WARM` (quente) e `GLASS` / `LAMP_COOL` (frio). Equilíbrio quente/frio:
  refletor principal quente pela frente-direita, preenchimento frio pela esquerda, sol da porta.
- Texto no mundo: escuro (`GUNMETAL`) sobre parede branca, `TEXT` sobre faixa `PANEL`.
  Placas principais em inglês com subtítulo em português.

## Componentes do tema / theme components

Variações (`theme_type_variation`) disponíveis em `ui/margin_theme.tres` — veja a vitrine
`scenes/ui/ui_kit.tscn`:

| Tipo | Variações |
|---|---|
| PanelContainer | (padrão: vidro com sombra), `TopBarPanel`, `ReadoutPanel`, `FloatPanel`, `SubPanel`, `ToolGroup`, `CardPanel`, `CardFlat`, `CardHover`, `ToastPanel`, `BarTrack`, `Chip`, `ChipOk`, `ChipWarn`, `ChipDanger`, `ChipInfo`, `ChipAccent` |
| Button | (padrão), `FlatButton`, `PrimaryButton`, `SegmentButton`, `SymButton`, `IconToggle`, `PartCard`, `MarkerToggle` |
| Label | `TitleLabel`, `CardTitle`, `SectionLabel`, `CaptionLabel`, `DimLabel`, `ValueLabel`, `BigValueLabel`, `AccentLabel`, `LogoLabel`, `MonoLabel`, `KeyCap` |
| Outros | `LineEdit` (halo de foco), `CheckButton` (switch), `CheckBox`, `OptionButton`, `PopupMenu`, `PopupPanel`, `ProgressBar`, `H/VSlider` (botão redondo), barras de rolagem finas, tooltips |

## Emblema MARGIN / MARGIN emblem

`ui/kit/emblem_margin.svg` (gerado por `make_ui_kit.py`, importado a 2048 px com mipmaps).
Arte original, **sem nenhuma insígnia ou logotipo da NASA / Space Apps**: patch redondo com
aro `INK` e costura `ACCENT`, 24 marcas de relógio em `ACCENT_2` (as fases da missão), campo
de espaço profundo com estrelas de quatro pontas, o limbo azul de um planeta com uma costa em
voxels, uma órbita elíptica que cruza um foguete branco subindo (faixa laranja, aletas
laranja, janela azul) com um satélite no ponto da órbita, e uma fita laranja com a palavra
MARGIN desenhada com traços geométricos (sem `<text>`, porque o rasterizador de SVG do Godot
ignora fontes). Aparece no hangar como placa de 32 m na parede esquerda (anel de luz quente),
como decalque de 15 m no piso ao lado do pad e no topo do banner do evento.

O banner do evento traz só texto: "NASA / SPACE APPS / CHALLENGE / 2026" e
"MISSION DESIGN GAME · JOGO DE PROJETO DE MISSÕES".

## Cenas / scenes

- `scenes/environment/vab.tscn` — prédio (gerado). Porta aberta de 60 × 96 m na parede do
  fundo (x de −45 a 15, alinhada às colunas), folhas recolhidas para cima e por fora da parede.
- `scenes/environment/outside_launch_site.tscn` — planeta lá fora (gerado, instanciado pelo
  VAB): cúpula de céu com sol e nuvens (`shaders/sky_dome.gdshader`), sol direcional com
  sombras, chão de grama em pixels voxel + praia + oceano (`shaders/outside_ground.gdshader`),
  terreno voxel com montanhas e neve (MultiMesh), árvores e nuvens voxel, pátio de concreto,
  crawlerway com postes de luz, complexo de lançamento A e um pad B menor ao fundo.
- `shaders/cutaway_solid.gdshader` — colunas, vigas, passarelas e treliças do teto somem
  quando a câmera sai do prédio por aquele lado, como as paredes (vista em corte limpa).
"""

EMBLEM_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
svg/scale=4.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_frames()
    files = {f"{name}.svg": body for name, (body, _, _) in FRAMES.items()}
    files.update({
        "divider.svg": divider(),
        "knob.svg": knob(False),
        "knob_hover.svg": knob(True),
        "switch_on.svg": switch(True),
        "switch_off.svg": switch(False),
        "check_on.svg": checkbox(True),
        "check_off.svg": checkbox(False),
        "emblem_margin.svg": emblem(),
    })
    for name, body in ICONS.items():
        px = BIG_ICONS.get(name, ICON_PX)
        files[f"icon_{name}.svg"] = svg(48, 48, body, px, px)
    files["icon_close_small.svg"] = svg(48, 48, ICONS["close"], 16, 16)
    for n in SYMMETRY_MODES:
        files[f"icon_sym_{n}.svg"] = svg(48, 48, sym_icon(n), 32, 32)
    for name, content in files.items():
        (OUT / name).write_text(content, encoding="utf-8", newline="\n")
    imp = OUT / "emblem_margin.svg.import"
    if not imp.exists():
        imp.write_text(EMBLEM_IMPORT, encoding="utf-8", newline="\n")
    build_theme()
    (ROOT / "ui" / "palette.gd").write_text(palette_gd(), encoding="utf-8", newline="\n")
    (ROOT / "docs" / "art").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs" / "art" / "palette_swatches.svg").write_text(swatches_svg(), encoding="utf-8", newline="\n")
    (ROOT / "docs" / "art" / "palette.md").write_text(palette_md(), encoding="utf-8", newline="\n")
    print(f"{len(files)} files -> {OUT}; ui/margin_theme.tres; ui/palette.gd; docs/art/palette.md + swatches")


if __name__ == "__main__":
    main()
