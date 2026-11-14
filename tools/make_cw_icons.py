"""Cometworks line icons (GDD section 22.7): 32x32, 1.5 px white strokes, square caps,
straight corners. Buttons tint them through the theme's icon colours.

Usage: python tools/make_cw_icons.py   ->  ui/cometworks/icons/*.svg
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "ui" / "cometworks" / "icons"

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
        '<g fill="none" stroke="#ffffff" stroke-width="1.6" stroke-linecap="square" stroke-linejoin="miter">')
TAIL = "</g></svg>\n"

ICONS = {
    # logo mark: the four-point star of the Cometlings' antenna bulb, with a short tail
    "star": '<path d="M16 3 L18.6 13.4 L29 16 L18.6 18.6 L16 29 L13.4 18.6 L3 16 L13.4 13.4 Z" fill="#ffffff" stroke="none"/>',
    # a Cometling head: round head, two tail-ears, star antenna
    "crew": '<circle cx="16" cy="18" r="7"/><path d="M10 14 L4 10 M22 14 L28 10"/><path d="M16 11 V6"/>'
            '<path d="M16 3 L17 5 L19 6 L17 7 L16 9 L15 7 L13 6 L15 5 Z" fill="#ffffff" stroke="none"/>'
            '<path d="M13 18 h0.5 M18.5 18 h0.5"/><path d="M9 28 h14"/>',
    # research: a four-point star inside an orbit ellipse
    "research": '<ellipse cx="16" cy="16" rx="12" ry="5" transform="rotate(-25 16 16)"/>'
                '<path d="M16 9 L17.6 14.4 L23 16 L17.6 17.6 L16 23 L14.4 17.6 L9 16 L14.4 14.4 Z"/>',
    # contracts: clipboard with lines and a check
    "contracts": '<path d="M9 6 H23 V28 H9 Z"/><path d="M13 4 H19 V8 H13 Z"/>'
                 '<path d="M12 14 H20 M12 18 H20 M12 22 H16"/><path d="M17 23 L19 25 L23 20"/>',
    # build: a lot outline with a crane hook
    "build": '<path d="M4 27 H28"/><path d="M8 27 V12 H15 V27"/><path d="M8 17 H15 M8 22 H15"/>'
             '<path d="M19 27 V6 H28 M19 6 L24 11"/><path d="M26 6 V12 M24.5 12 H27.5"/>',
    # map: orbit with a body and a small craft
    "map": '<circle cx="16" cy="16" r="3.5"/><ellipse cx="16" cy="16" rx="12" ry="7"/>'
           '<path d="M25 11 L28 9 L27 12 Z"/>',
    # race: flag on a pole
    "race": '<path d="M8 28 V4"/><path d="M8 5 H25 L21 10 L25 15 H8"/>',
    # encyclopedia: open book
    "book": '<path d="M4 8 C8 6 12 6 16 9 C20 6 24 6 28 8 V25 C24 23 20 23 16 26 C12 23 8 23 4 25 Z"/>'
            '<path d="M16 9 V26"/>',
    # finance: coin stack / credits
    "finance": '<ellipse cx="16" cy="9" rx="9" ry="3.5"/><path d="M7 9 V15 C7 17 11 18.5 16 18.5 C21 18.5 25 17 25 15 V9"/>'
               '<path d="M7 15 V21 C7 23 11 24.5 16 24.5 C21 24.5 25 23 25 21 V15"/>',
    # settings: square gear-ish (straight corners on purpose)
    "settings": '<path d="M13 4 H19 V8 L22 9.5 L25 6.5 L29.5 11 L26.5 14 V18 L29.5 21 L25 25.5 L22 22.5 L19 24 V28 H13 '
                'V24 L10 22.5 L7 25.5 L2.5 21 L5.5 18 V14 L2.5 11 L7 6.5 L10 9.5 L13 8 Z"/><circle cx="16" cy="16" r="4"/>',
    # buildings
    "hq": '<path d="M5 27 H27"/><path d="M8 27 V11 L16 6 L24 11 V27"/><path d="M13 27 V20 H19 V27"/>'
          '<path d="M11 14 H13 M19 14 H21"/>',
    "hangar": '<path d="M3 27 H29"/><path d="M5 27 V13 C5 8 27 8 27 13 V27"/><path d="M11 27 V16 H21 V27"/>'
              '<path d="M16 16 V27"/>',
    "pad": '<path d="M5 27 H27"/><path d="M9 27 V7 M9 10 H13 M9 16 H13 M9 22 H13"/>'
           '<path d="M19 26 V12 L21 8 L23 12 V26 Z"/><path d="M17 26 L19 22 M25 26 L23 22"/>',
    "lab": '<path d="M12 4 H20 M13 4 V13 L6 26 H26 L19 13 V4"/><path d="M9 21 H23"/>',
    "control": '<path d="M4 7 H28 V21 H4 Z"/><path d="M12 27 H20 M16 21 V27"/>'
               '<path d="M8 17 C11 11 16 11 19 13 C21 14 23 13 24 11"/>',
    "antenna": '<path d="M7 9 C7 17 15 23 23 23 Z"/><path d="M15 16 L24 7"/><path d="M14 26 L17 19 L20 26 Z"/>'
               '<path d="M24 4 C26 4 28 6 28 8"/>',
    "training": '<circle cx="16" cy="16" r="11"/><circle cx="16" cy="16" r="6"/><circle cx="16" cy="16" r="1.5"/>',
    "factory": '<path d="M3 27 H29"/><path d="M5 27 V15 L11 19 V15 L17 19 V15 L23 19 V8 H27 V27"/>'
               '<path d="M9 23 H12 M15 23 H18"/>',
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, body in ICONS.items():
        (OUT / f"{name}.svg").write_text(HEAD + body + TAIL, encoding="utf-8")
    print("wrote", len(ICONS), "icons to", OUT)


if __name__ == "__main__":
    main()
