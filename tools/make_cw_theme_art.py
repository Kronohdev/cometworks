"""Writes the small SVG widgets of the Cometworks theme (ui/cometworks_theme.tres) into
ui/cometworks/theme/: check boxes, radio buttons, the two-position lever toggle, slider and
throttle grabbers, chevrons, the spin box arrows and the item-list / tree markers.

Art direction "Aurora de observatorio" (docs/GDD_Cometworks.pdf section 22): 1.5 px strokes,
square corners (2 px radius at most), engraved hairlines, teal for "on", no glow.

The SVGs are plain text: tweak them by hand or here and run
    python tools/make_cw_theme_art.py
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "ui" / "cometworks" / "theme"

SPACE = "#070b14"
WELL = "#0a1120"
PANEL = "#0e1524"
RAISED = "#152036"
LINE = "#24324d"
HAIR = "#3a4d72"
HOVER = "#1d2a44"
TEXT = "#e9eef7"
DIM = "#8c9ab5"
TEAL = "#3fe0c5"
ICE = "#bfe8ff"
IGN = "#ff8a3d"


def svg(w, h, body, opacity=1.0):
    g = f'<g opacity="{opacity}">' if opacity < 1.0 else "<g>"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f"{g}{body}</g></svg>\n")


def check(on, hover=False):
    edge = TEAL if on else (ICE if hover else HAIR)
    body = f'<rect x="1.5" y="1.5" width="15" height="15" rx="1.5" fill="{WELL}" stroke="{edge}" stroke-width="1.2"/>'
    if on:
        body += (f'<rect x="4" y="4" width="10" height="10" fill="{TEAL}" opacity="0.18"/>'
                 f'<path d="M5 9.2 L7.8 12 L13 6" fill="none" stroke="{TEAL}" stroke-width="1.8" '
                 'stroke-linecap="square" stroke-linejoin="miter"/>')
    return body


def radio(on):
    edge = TEAL if on else HAIR
    body = f'<circle cx="9" cy="9" r="7" fill="{WELL}" stroke="{edge}" stroke-width="1.2"/>'
    if on:
        body += f'<rect x="6" y="6" width="6" height="6" transform="rotate(45 9 9)" fill="{TEAL}"/>'
    return body


def lever(on):
    """Two-position instrument toggle (GDD 22.4: "alavancas de duas posicoes, nao pilulas")."""
    slot = (f'<rect x="1.5" y="4.5" width="35" height="13" rx="2" fill="{SPACE}" stroke="{HAIR}" stroke-width="1"/>'
            f'<path d="M7 11 H31" stroke="#000000" stroke-width="3" opacity="0.6"/>')
    kx = 22 if on else 2
    cap = TEAL if on else DIM
    knob = (f'<rect x="{kx + 0.6}" y="1.6" width="12.8" height="18.8" rx="1.5" fill="{HOVER if on else RAISED}" '
            f'stroke="{cap}" stroke-width="1.2"/>'
            f'<path d="M{kx + 4} 8 H{kx + 10} M{kx + 4} 11 H{kx + 10} M{kx + 4} 14 H{kx + 10}" '
            f'stroke="{cap}" stroke-width="1"/>')
    led = f'<rect x="{6 if on else 28}" y="9" width="4" height="4" fill="{TEAL if on else LINE}"/>'
    return slot + led + knob


def hgrab(state):
    """Horizontal slider grabber: a fader cap."""
    edge = {"n": ICE, "h": "#ffffff", "d": HAIR}[state]
    fill = RAISED if state != "h" else "#1d2a44"
    return (f'<rect x="1" y="1" width="12" height="20" rx="1.5" fill="{fill}" stroke="{edge}" stroke-width="1.2"/>'
            f'<path d="M3.5 11 H10.5" stroke="{TEAL if state != "d" else HAIR}" stroke-width="1.6"/>'
            f'<path d="M4 7.5 H10 M4 14.5 H10" stroke="{edge}" stroke-width="0.9" opacity="0.6"/>')


def vgrab(state):
    """Vertical slider grabber: the throttle lever head (GDD 22.4 "sliders de fase")."""
    edge = {"n": ICE, "h": "#ffffff", "d": HAIR}[state]
    fill = RAISED if state != "h" else "#1d2a44"
    return (f'<rect x="1" y="1" width="26" height="12" rx="1.5" fill="{fill}" stroke="{edge}" stroke-width="1.2"/>'
            f'<path d="M3 7 H25" stroke="{IGN if state != "d" else HAIR}" stroke-width="1.6"/>'
            f'<path d="M7 3.5 V10.5 M21 3.5 V10.5" stroke="{edge}" stroke-width="0.9" opacity="0.55"/>')


def tick():
    return f'<rect x="0" y="0" width="1" height="8" fill="{HAIR}"/>'


def chevron(d, col=DIM, w=12, h=12):
    paths = {"down": "M2.5 4.5 L6 8 L9.5 4.5", "right": "M4.5 2.5 L8 6 L4.5 9.5",
             "left": "M7.5 2.5 L4 6 L7.5 9.5", "up": "M2.5 7.5 L6 4 L9.5 7.5"}
    return f'<path d="{paths[d]}" fill="none" stroke="{col}" stroke-width="1.5" stroke-linecap="square"/>'


def updown():
    return (f'<path d="M3 6.5 L6 3.5 L9 6.5" fill="none" stroke="{DIM}" stroke-width="1.4" stroke-linecap="square"/>'
            f'<path d="M3 11.5 L6 14.5 L9 11.5" fill="none" stroke="{DIM}" stroke-width="1.4" stroke-linecap="square"/>')


def close_x(col=DIM):
    return f'<path d="M3.5 3.5 L10.5 10.5 M10.5 3.5 L3.5 10.5" stroke="{col}" stroke-width="1.5" stroke-linecap="square"/>'


def grip():
    return "".join(f'<rect x="{x}" y="{y}" width="1.5" height="1.5" fill="{HAIR}"/>'
                   for x in (2, 6) for y in (2, 6, 10))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "check_off.svg": svg(18, 18, check(False)),
        "check_off_hover.svg": svg(18, 18, check(False, True)),
        "check_on.svg": svg(18, 18, check(True)),
        "check_off_disabled.svg": svg(18, 18, check(False), 0.4),
        "check_on_disabled.svg": svg(18, 18, check(True), 0.4),
        "radio_off.svg": svg(18, 18, radio(False)),
        "radio_on.svg": svg(18, 18, radio(True)),
        "radio_off_disabled.svg": svg(18, 18, radio(False), 0.4),
        "radio_on_disabled.svg": svg(18, 18, radio(True), 0.4),
        "lever_off.svg": svg(38, 22, lever(False)),
        "lever_on.svg": svg(38, 22, lever(True)),
        "lever_off_disabled.svg": svg(38, 22, lever(False), 0.4),
        "lever_on_disabled.svg": svg(38, 22, lever(True), 0.4),
        "hslider_grabber.svg": svg(14, 22, hgrab("n")),
        "hslider_grabber_hl.svg": svg(14, 22, hgrab("h")),
        "hslider_grabber_disabled.svg": svg(14, 22, hgrab("d")),
        "vslider_grabber.svg": svg(28, 14, vgrab("n")),
        "vslider_grabber_hl.svg": svg(28, 14, vgrab("h")),
        "vslider_grabber_disabled.svg": svg(28, 14, vgrab("d")),
        "slider_tick.svg": svg(1, 8, tick()),
        "vslider_tick.svg": svg(22, 1, f'<rect x="0" y="0" width="22" height="1" fill="{HAIR}"/>'),
        "chevron_down.svg": svg(12, 12, chevron("down")),
        "chevron_right.svg": svg(12, 12, chevron("right")),
        "chevron_left.svg": svg(12, 12, chevron("left")),
        "chevron_up.svg": svg(12, 12, chevron("up")),
        "chevron_down_hl.svg": svg(12, 12, chevron("down", TEAL)),
        "chevron_right_hl.svg": svg(12, 12, chevron("right", TEAL)),
        "updown.svg": svg(12, 18, updown()),
        "close.svg": svg(14, 14, close_x()),
        "close_hl.svg": svg(14, 14, close_x(TEXT)),
        "grip.svg": svg(10, 14, grip()),
    }
    for name, text in files.items():
        (OUT / name).write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {len(files)} svgs to {OUT}")
    grain()


def grain(size=128, seed=7):
    """Tileable panel grain (GDD 22.3 "grao fino"): white and black specks in the alpha channel;
    CwPanelStyle draws it at a few percent over the panel fill."""
    import numpy as np
    from PIL import Image
    rng = np.random.default_rng(seed)
    n = rng.normal(0.0, 1.0, (size, size))
    # a touch of low-frequency mottling so it reads as paint, not as TV noise
    lo = rng.normal(0.0, 1.0, (size // 8, size // 8))
    lo = np.kron(lo, np.ones((8, 8)))
    for _ in range(2):
        lo = (lo + np.roll(lo, 1, 0) + np.roll(lo, -1, 0) + np.roll(lo, 1, 1) + np.roll(lo, -1, 1)) / 5.0
    v = n + lo * 0.6
    a = np.clip(np.abs(v) / 2.6, 0, 1)
    rgb = np.where(v > 0, 255, 0).astype(np.uint8)
    img = np.dstack([rgb, rgb, rgb, (a * 255).astype(np.uint8)])
    Image.fromarray(img, "RGBA").save(OUT / "grain.png", optimize=True)
    print("wrote grain.png")


if __name__ == "__main__":
    main()
