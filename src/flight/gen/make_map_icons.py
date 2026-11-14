"""Writes the map / maneuver-node icons (scenes/flight/ui/map_*.svg, marker_maneuver.svg).

White strokes over a dark halo: the scenes tint them (self_modulate) with palette colours
(docs/art/palette.md: DATA_6 prograde, DATA_4 normal, DATA_3 radial, DATA_1 maneuver).
Run: python src/flight/gen/make_map_icons.py
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "..", "scenes", "flight", "ui")
HALO = 'stroke="#0a0e13" stroke-opacity="0.6"'


def icon(name, body, size=64, halo_w=7.0, w=3.6, color="#ffffff"):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 64 64">
  <g fill="none" {HALO} stroke-width="{halo_w}" stroke-linecap="round" stroke-linejoin="round">
{body}
  </g>
  <g fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">
{body}
  </g>
</svg>
'''
    with open(os.path.join(OUT, name), "w", newline="\n") as f:
        f.write(svg)


def main():
    icon("map_prograde.svg", '''    <circle cx="32" cy="32" r="12"/>
    <line x1="32" y1="20" x2="32" y2="8"/>
    <line x1="20" y1="32" x2="7" y2="32"/>
    <line x1="44" y1="32" x2="57" y2="32"/>
    <circle cx="32" cy="32" r="1.5"/>''')
    icon("map_retrograde.svg", '''    <circle cx="32" cy="32" r="12"/>
    <line x1="24" y1="24" x2="40" y2="40"/>
    <line x1="40" y1="24" x2="24" y2="40"/>
    <line x1="32" y1="44" x2="32" y2="56"/>
    <line x1="21.5" y1="41" x2="13" y2="49.5"/>
    <line x1="42.5" y1="41" x2="51" y2="49.5"/>''')
    icon("map_normal.svg", '''    <path d="M32 14 L48 42 L16 42 Z"/>
    <circle cx="32" cy="33" r="2"/>''')
    icon("map_antinormal.svg", '''    <path d="M32 46 L48 18 L16 18 Z"/>
    <line x1="32" y1="18" x2="32" y2="8"/>
    <line x1="16" y1="18" x2="9" y2="12"/>
    <line x1="48" y1="18" x2="55" y2="12"/>''')
    icon("map_radial_out.svg", '''    <circle cx="32" cy="32" r="11"/>
    <circle cx="32" cy="32" r="1.5"/>
    <line x1="40" y1="24" x2="49" y2="15"/>
    <line x1="24" y1="24" x2="15" y2="15"/>
    <line x1="40" y1="40" x2="49" y2="49"/>
    <line x1="24" y1="40" x2="15" y2="49"/>''')
    icon("map_radial_in.svg", '''    <circle cx="32" cy="32" r="14"/>
    <line x1="42" y1="22" x2="35.5" y2="28.5"/>
    <line x1="22" y1="22" x2="28.5" y2="28.5"/>
    <line x1="42" y1="42" x2="35.5" y2="35.5"/>
    <line x1="22" y1="42" x2="28.5" y2="35.5"/>''')
    icon("map_node.svg", '''    <circle cx="32" cy="32" r="15"/>
    <path d="M32 17 L32 25 M19 39.5 L26 35.5 M45 39.5 L38 35.5"/>
    <circle cx="32" cy="32" r="3.2"/>''', w=4.0)
    icon("marker_maneuver.svg", '''    <circle cx="32" cy="32" r="15"/>
    <path d="M32 17 L32 26 M19 39.5 L26.5 35 M45 39.5 L37.5 35"/>
    <circle cx="32" cy="32" r="2.6"/>''', w=4.0, color="#6aa9ff")
    icon("map_soi.svg", '''    <circle cx="32" cy="32" r="13"/>
    <path d="M32 32 L32 32"/>
    <path d="M44 20 L54 10 M46 10 L54 10 L54 18"/>''')
    icon("map_impact.svg", '''    <circle cx="32" cy="32" r="14"/>
    <line x1="24" y1="24" x2="40" y2="40"/>
    <line x1="40" y1="24" x2="24" y2="40"/>''')
    icon("map_closest.svg", '''    <path d="M10 22 L28 32 L10 42 Z"/>
    <path d="M54 22 L36 32 L54 42 Z"/>''')
    icon("map_add.svg", '''    <circle cx="32" cy="32" r="13"/>
    <line x1="32" y1="25" x2="32" y2="39"/>
    <line x1="25" y1="32" x2="39" y2="32"/>''', w=3.2)
    icon("map_node_line.svg", '''    <circle cx="32" cy="32" r="9"/>
    <line x1="32" y1="14" x2="32" y2="50"/>''')
    icon("map_delete.svg", '''    <line x1="22" y1="22" x2="42" y2="42"/>
    <line x1="42" y1="22" x2="22" y2="42"/>''', w=4.2)
    icon("map_body.svg", '''    <circle cx="32" cy="32" r="9"/>''', w=4.0)


if __name__ == "__main__":
    main()
