"""Writes the Cometworks campus buildings (GDD sections 4 and 11) as voxel models.

  assets/campus/<kind>/<kind>_e<era>_l<level>.glb   one model per era and level. Nodes:
        Base       always shown: floor, interior, wall stubs (1 m), yard props
        CutRoof    roof and rooftop props        } hidden by src/tycoon/campus_building.gd
        CutPX/NX/PZ/NZ  upper walls by facing    } when the camera comes close (cutaway)
        CutUpper   whole upper storeys           }
  assets/campus/<kind>/<kind>_scaffold.glb       the construction look
  assets/campus/pad/rocket_e<era>.glb            the rocket standing on a pad
  scenes/tycoon/buildings/<kind>.tscn            Era1..5 / Level1..3 (cumulative) with the
                                                 models and their lights, Scaffold, Spots

Voxels are 10 cm with baked AO (tools/campus_voxel.py); every model shares
assets/campus/campus_voxel.tres (shaders/campus_voxel.gdshader) through the import
settings, so the scenes stay editable. Interiors: HQ offices and meeting room, workshop
with a stage on cradles and a high bay, pad blockhouse, lab benches and a telescope dome,
mission control consoles, radio hut, gym, factory line.

Spots: walk targets for the campus Cometlings (src/tycoon/campus_walker.gd walks
spot -> door -> road -> door -> spot in straight lines). Door markers sit on the road side
(local z = +9) straight out from the doorway; interior spots add a `via` point just inside
the doorway. The script checks the legs against the voxels and prints any that clip props.

Usage: python tools/build_campus_buildings.py [kind ...]   (also run by build_campus_scene.py)
"""
import math
import sys
import time
from functools import lru_cache
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import campus_voxel as cv  # noqa: E402
from campus_voxel import Grid, Stamp, BASE, ROOF, UPPER  # noqa: E402
import campus_kit as K  # noqa: E402
from campus_kit import C, STYLES, Room, build_room, T  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "campus"
RES = "res://assets/campus"
MAT = "res://assets/campus/campus_voxel.tres"
OUT_BUILD = ROOT / "scenes" / "tycoon" / "buildings"
DOOR_Z = 9.0           # door markers sit on the road side of every lot (local +z)
MODEL_Y = -0.05        # models sit half a voxel low so the floor top is 5 cm over the grass

LOT_SIZE = {"hq": (18, 13), "workshop": (26, 17), "pad": (17, 17), "lab": (20, 13), "control": (16, 12),
            "antenna": (15, 15), "training": (16, 13), "factory": (22, 13)}
HEIGHT = {"hq": 13.5, "workshop": 18, "pad": 22, "lab": 11, "control": 12, "antenna": 12, "training": 9,
          "factory": 12}


class Ctx:
    def __init__(self, st):
        self.st = st
        self.lights = []
        self.props = []        # shared models: (key, x, y, z, turn, node name)

    def shared(self, g, key, x, z, turn=0, y=0.1, name=None):
        """Places a shared model (assets/campus/props/<key>.glb, one file for every era):
        the scene instances it, and the voxels go into the grid untagged, so they are not
        meshed again but still darken the floor (AO) and block the path check."""
        g.stamp(SHARED[key](), x, z, turn, y, tag=0)
        self.props.append((key, x, y, z, turn, name or "Prop"))

    def light(self, x, y, z, color=None, energy=None, rng=6.0, shadow=False):
        self.lights.append((x, y, z, color or self.st["light"], energy or self.st["light_e"], rng, shadow))


def put(g, s, x, z, turn=0, y=0.1, tag=None):
    g.stamp(s, x, z, turn, y, tag)


# big props that look the same in every era: one model each, instanced by the scenes
SHARED = {
    "dish_s": lambda: K.dish(3, 0.9, 0.5, 1.0), "dish_hq": lambda: K.dish(3, 1.0, 0.7, 1.2),
    "dish_m": lambda: K.dish(3, 1.4, 0.5, 1.8), "dish_l": lambda: K.dish(3, 2.0, 0.6, 2.5),
    "dish_xl": lambda: K.dish(3, 3.4, 0.7, 3.5), "dish_n": lambda: K.dish(3, 1.6, 0.5, 2.2),
    "dish_n2": lambda: K.dish(3, 1.6, 0.8, 2.2),
    "rocket_v": lambda: K.rocket_v(3, 8.0, 0.9), "rocket_h": lambda: K.rocket_h(3, 5.0, 0.8),
    "tank_s": lambda: K.big_tank(3, 2.4, 0.7), "tank_m": lambda: K.big_tank(3, 3.2, 0.9),
    "tank_f": lambda: K.big_tank(3, 3.0, 0.9),
    "obs_dome": lambda: K.dome(3, 2.0, slit=True), "obs_dome5": lambda: K.dome(5, 2.0, slit=True),
    "telescope": lambda: K.telescope(3),
}


# ------------------------------------------------------------------ extra stamps
@lru_cache(None)
def emblem(era, r=0.7):
    """the agency star on a disc, wall-mounted (back against -z)"""
    st = STYLES[era]
    s = Stamp(2 * r + 0.4, 2 * r + 2.4, 0.4)
    yc = 2.0 + r
    disc = {1: C["ink"], 2: P_("#2e4d8b"), 3: C["white"], 4: C["ink"], 5: st["wall_dk"]}[era]
    s.cyl_z(0, yc, r, -0.2, -0.1, disc)
    s.cyl_z(0, yc, r + 0.1, -0.2, -0.1, st["accent"] if era != 3 else C["orange"], rin=r - 0.05)
    K._sparkle(s, 0.0, yc, -0.1, 0.0, C["orange_glow"] if era != 5 else C["violet_glow"], sc=0.1)
    return s


def P_(h, glow=0.0):
    return cv.PAL(h, glow)


@lru_cache(None)
def coffee_table(era):
    st = STYLES[era]
    s = Stamp(1.2, 0.8, 0.8)
    s.box(-0.5, 0.5, 0.35, 0.45, -0.3, 0.3, st["desk_top"])
    for (x, z) in ((-0.45, -0.25), (0.35, -0.25), (-0.45, 0.15), (0.35, 0.15)):
        s.box(x, x + 0.1, 0.0, 0.35, z, z + 0.1, st["desk"])
    s.box(-0.3, -0.1, 0.45, 0.55, -0.1, 0.1, C["red"])
    s.box(0.1, 0.4, 0.45, 0.5, -0.2, 0.1, C["paper"])
    return s


@lru_cache(None)
def mini_rocket(era):
    s = Stamp(0.8, 2.2, 0.8)
    s.box(-0.3, 0.3, 0.0, 0.9, -0.3, 0.3, STYLES[era]["cab"])
    s.box(-0.35, 0.35, 0.9, 1.0, -0.35, 0.35, STYLES[era]["desk_top"])
    s.box(-0.1, 0.1, 1.0, 1.8, -0.1, 0.1, C["rocket"])
    s.box(-0.05, 0.05, 1.8, 2.0, -0.05, 0.05, C["orange"])
    s.box(-0.2, 0.2, 1.0, 1.2, -0.05, 0.05, C["orange"])
    s.box(-0.05, 0.05, 1.0, 1.2, -0.2, 0.2, C["orange"])
    return s


@lru_cache(None)
def big_desk(era):
    """director's desk: the director sits on +z"""
    st = STYLES[era]
    s = Stamp(2.4, 1.4, 1.6)
    s.box(-1.1, 1.1, 0.7, 0.8, -0.5, 0.4, st["desk_top"])
    s.box(-1.1, 1.1, 0.0, 0.7, -0.5, -0.3, st["desk"])
    s.box(-1.1, -0.7, 0.0, 0.7, -0.5, 0.4, st["desk"])
    s.box(0.7, 1.1, 0.0, 0.7, -0.5, 0.4, st["desk"])
    K.monitor(s, st, -0.4, 0.2, 0.8)
    s.box(0.3, 0.8, 0.8, 0.85, -0.3, 0.1, C["paper"])
    s.box(0.5, 0.7, 0.8, 1.0, 0.2, 0.3, C["leaf"])
    K._sparkle(s, 0.0, 0.4, -0.6, -0.5, st["accent"], sc=0.05)
    K.chair(s, st, 0.0, 0.75, 1, col=st["chair2"])
    return s


@lru_cache(None)
def bleachers(era, w=3.0):
    st = STYLES[era]
    s = Stamp(1.6, 1.4, w)
    for k in range(3):
        s.box(-0.7 + k * 0.5, 0.7, 0.0, 0.4 + k * 0.4, -w / 2, w / 2, C["concrete"] if era > 1 else C["crate"])
        s.box(-0.7 + k * 0.5, -0.5 + k * 0.5, 0.3 + k * 0.4, 0.4 + k * 0.4, -w / 2, w / 2,
              (st["chair"], st["accent"], C["blue"])[k])
    return s


@lru_cache(None)
def centrifuge(era):
    st = STYLES[era]
    s = Stamp(5.2, 2.6, 2.0)
    s.cyl_y(0, 0, 0.5, 0.0, 2.0, st["metal_dk"])
    s.cyl_y(0, 0, 0.7, 0.0, 0.3, C["ink"])
    s.box(-2.2, 2.2, 1.6, 1.9, -0.2, 0.2, st["accent"] if era != 4 else st["led"])
    s.box(1.6, 2.5, 1.0, 2.0, -0.5, 0.5, C["white"])
    s.box(2.5, 2.6, 1.3, 1.7, -0.3, 0.3, st["screen"])
    s.box(-2.5, -1.8, 1.2, 1.9, -0.4, 0.4, st["metal"])
    s.box(-0.1, 0.1, 2.0, 2.4, -0.1, 0.1, C["red_glow"])
    return s


@lru_cache(None)
def sim_capsule(era):
    st = STYLES[era]
    s = Stamp(2.0, 2.2, 2.0)
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    m = (Y > 0.2) & (Y < 1.9) & (R < 0.9 - (Y - 0.2) * 0.3)
    s.mask(m, C["white"])
    s.mask(m & (Y > 0.2) & (Y < 0.4), C["ink"])
    s.box(-0.3, 0.3, 0.8, 1.3, 0.55, 0.75, st["screen2"])
    s.box(-0.9, 0.9, 0.0, 0.2, -0.9, 0.9, st["metal_dk"])
    return s


@lru_cache(None)
def silo(era, r=1.2, h=7.0):
    st = STYLES[era]
    s = Stamp(2 * r + 0.8, h + 1.6, 2 * r + 0.8)
    col = {1: C["crate"], 2: C["grey_lt"], 3: C["white"], 4: st["wall"][0], 5: st["wall"][0]}[era]
    s.cyl_y(0, 0, r, 0.0, h, col)
    for y in np.arange(1.0, h, 1.5):
        s.cyl_y(0, 0, r + 0.05, y, y + 0.1, st["metal_dk"] if era != 4 else st["led"])
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    s.mask((Y >= h) & (Y < h + r * 0.8) & (R < r - (Y - h) / 0.8), st["roof"][0] if era != 3 else C["orange"])
    for y in np.arange(0.3, h, 0.4):     # ladder
        s.box(-0.2, 0.2, y, y + 0.05, r - 0.05, r + 0.15, st["metal_dk"])
    s.box(-0.25, -0.2, 0.0, h + 0.4, r, r + 0.15, st["metal_dk"])
    s.box(0.2, 0.25, 0.0, h + 0.4, r, r + 0.15, st["metal_dk"])
    return s


def hazard_box(g, x0, x1, z0, z1):
    """yellow-and-black work area outline painted into the floor"""
    s, X, Y, Z = g.region(x0, x1, 0.0, 0.1, z0, z1)
    edge = (X < x0 + 0.15) | (X > x1 - 0.15) | (Z < z0 + 0.15) | (Z > z1 - 0.15)
    stripe = (np.floor((X + Z) * 10 / 3 + 1e-6) % 2) == 0
    g.put_mask(s, edge & stripe, C["hazard"], only_filled=True)
    g.put_mask(s, edge & ~stripe, C["ink"], only_filled=True)


def lane(g, x, z0, z1):
    """a dashed yellow walking lane line on the floor along z"""
    s, X, Y, Z = g.region(x - 0.05, x + 0.05, 0.0, 0.1, min(z0, z1), max(z0, z1))
    g.put_mask(s, (np.floor(Z * 10 / 4 + 1e-6) % 2) == 0, C["hazard"], only_filled=True)


@lru_cache(None)
def exercise_bike(era):
    st = STYLES[era]
    s = Stamp(0.8, 1.4, 1.4)
    s.box(-0.2, 0.2, 0.0, 0.1, -0.6, 0.6, st["metal_dk"])
    s.box(-0.05, 0.05, 0.1, 0.8, 0.2, 0.3, st["metal_dk"])
    s.box(-0.15, 0.15, 0.8, 0.9, 0.1, 0.4, C["ink"])
    s.box(-0.05, 0.05, 0.1, 1.1, -0.4, -0.3, st["metal_dk"])
    s.box(-0.25, 0.25, 1.1, 1.2, -0.45, -0.35, st["metal_dk"])
    s.cyl_x(0.4, -0.05, 0.25, -0.05, 0.05, st["accent"])
    s.box(-0.1, 0.1, 1.2, 1.3, -0.45, -0.35, st["screen"])
    return s


@lru_cache(None)
def helmet_stand(era):
    """a space helmet on a plinth (the training centre's pride)"""
    st = STYLES[era]
    s = Stamp(0.8, 1.8, 0.8)
    s.box(-0.3, 0.3, 0.0, 0.9, -0.3, 0.3, st["cab"])
    s.box(-0.35, 0.35, 0.9, 1.0, -0.35, 0.35, st["desk_top"])
    s.sphere(0.0, 1.3, 0.0, 0.3, C["white"])
    s.box(-0.2, 0.2, 1.2, 1.45, 0.1, 0.3, C["ice_glow"])
    s.box(-0.3, 0.3, 1.0, 1.1, -0.3, 0.3, C["orange"])
    return s


@lru_cache(None)
def welding_cart(era):
    s = Stamp(1.0, 1.4, 0.8)
    s.box(-0.4, 0.4, 0.1, 0.8, -0.3, 0.3, C["red"])
    s.cyl_y(-0.2, 0.0, 0.12, 0.8, 1.3, C["leaf2"])
    s.cyl_y(0.15, 0.0, 0.12, 0.8, 1.2, C["grey"])
    s.box(-0.4, 0.4, 0.0, 0.1, -0.3, 0.3, C["rubber"])
    s.box(0.3, 0.4, 0.5, 0.6, 0.3, 0.4, C["orange_glow"])
    return s


def ring_platform(g, st, x0, x1, z0, z1, y, cx, cz, hole):
    s, X, Y, Z = g.region(x0, x1, y, y + 0.1, z0, z1)
    m = np.sqrt((X - cx) ** 2 + (Z - cz) ** 2) > hole
    g.put_mask(s, m, C["grey_dk"] if st["era"] != 1 else C["crate"])
    # rail on the open edge
    g.box(x0, x1, y + 0.9, y + 1.0, z1 - 0.1, z1, C["hazard"])
    for x in np.arange(x0, x1, 0.8):
        g.box(x, x + 0.1, y + 0.1, y + 0.9, z1 - 0.1, z1, C["hazard"])


def lattice(g, x0, x1, z0, z1, y0, y1, col, step=1.2):
    """open lattice tower: corner posts, rings and diagonal braces"""
    for (x, z) in ((x0, z0), (x1 - 0.2, z0), (x0, z1 - 0.2), (x1 - 0.2, z1 - 0.2)):
        g.box(x, x + 0.2, y0, y1, z, z + 0.2, col)
    y = y0 + step
    k = 0
    while y < y1:
        g.box(x0, x1, y, y + 0.1, z0, z0 + 0.1, col)
        g.box(x0, x1, y, y + 0.1, z1 - 0.1, z1, col)
        g.box(x0, x0 + 0.1, y, y + 0.1, z0, z1, col)
        g.box(x1 - 0.1, x1, y, y + 0.1, z0, z1, col)
        # braces
        n = int((x1 - x0) * 10)
        for i in range(n):
            yy = y - step + (i / n) * step if k % 2 == 0 else y - (i / n) * step
            xx = x0 + i * 0.1
            g.box(xx, xx + 0.1, round(yy, 1), round(yy, 1) + 0.1, z0, z0 + 0.1, col)
            g.box(xx, xx + 0.1, round(yy, 1), round(yy, 1) + 0.1, z1 - 0.1, z1, col)
        y += step
        k += 1


# ------------------------------------------------------------------ recipes
# Each recipe(g, st, level, ctx) paints ONE level (levels show cumulatively). Lots are
# rectangles around (0, 0) with the door side towards +z (the road).
def hq(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-5, 5, -5, 3, 3.8)
        build_room(g, st, r, doors=[("pz", 0.0, 2.4, 2.6)])
        put(g, K.rug(e, 3.0, 2.0), 0.0, -1.2)
        put(g, K.reception(e), 0.0, -3.8)
        put(g, emblem(e), 0.0, -4.5)
        put(g, K.desk(e, True, 0), -3.7, -2.0)
        put(g, K.desk(e, True, 1), -1.9, -2.0)
        put(g, K.desk(e, True, 2), -3.7, 0.6)
        put(g, K.desk(e, False, 3), -1.9, 0.6)
        put(g, K.poster(e, 0), -3.6, -4.5)
        put(g, K.poster(e, 1), -2.2, -4.5)
        put(g, K.whiteboard(e, 0, 2.0), -4.5, -0.7, turn=1)
        put(g, K.coffee_corner(e), 3.4, -4.2)
        put(g, K.water_cooler(e), 1.95, -4.3)
        put(g, K.rug(e, 2.2, 2.6), 3.4, -0.4)
        put(g, K.sofa(e, 2.0), 4.2, -0.4, turn=3)
        put(g, coffee_table(e), 3.0, -0.4, turn=1)
        put(g, K.floor_lamp(e), 4.3, 1.4)
        put(g, K.plant(2, 0), -4.2, -4.2)
        put(g, K.plant(1, 1), 4.2, 2.2)
        put(g, K.plant(1, 2), -4.2, 2.2)
        put(g, K.shelf(e, 2, 1.4, 2.0), 4.4, -2.4, turn=3)
        cx.light(-2.4, 3.0, -1.0, rng=6.5)
        cx.light(2.6, 3.0, -1.4, rng=6.0)
        cx.light(0.0, 2.3, 4.0, "#ffd29a", 1.0, 4.5)
        # yard
        put(g, K.banner(e), -3.4, 4.6, y=0.0)
        put(g, K.banner(e), 3.4, 4.6, y=0.0)
        put(g, K.planter(e, 2.2, 0.8, 0), -2.6, 3.7, y=0.0)
        put(g, K.planter(e, 2.2, 0.8, 1), 2.6, 3.7, y=0.0)
        put(g, K.mailbox(e), -1.9, 4.8, y=0.0)
        put(g, K.bike(e, 0), -8.3, 4.6, turn=1, y=0.0)
        put(g, K.bike(e, 1), -7.7, 4.6, turn=1, y=0.0)
        put(g, K.lamp_post(e), 5.6, 4.4, turn=3, y=0.0)
        cx.light(5.2, 3.0, 4.4, "#ffd29a", 0.8, 5.0)
    elif lv == 2:
        r = Room(-8.8, -5.2, -4.5, 2.5, 3.4)
        build_room(g, st, r, doors=[("pz", -7.0, 2.0, 2.5)], gable_axis="z")
        put(g, K.meeting_table(e, 2.8), -7.0, -2.0)
        put(g, K.big_screen(e, 2.4, 1.3, 1), -7.0, -4.1)
        put(g, K.plant(1, 3), -8.2, 1.8)
        put(g, K.plant(0, 1), -5.8, 1.9)
        put(g, K.poster(e, 2), -8.4, 0.2, turn=1)
        cx.light(-7.0, 2.7, -1.0, rng=5.0)
        put(g, K.bench(e), -4.8, 6.6, turn=2, y=0.0)
        put(g, K.planter(e, 1.6, 0.8, 2), -8.2, 3.4, y=0.0)
    else:
        r = Room(5.2, 8.8, -5.0, 1.5, 3.6)
        build_room(g, st, r, doors=[("pz", 7.0, 2.0, 2.5)], roof=False)
        put(g, big_desk(e), 7.0, -3.4, turn=2)
        put(g, K.shelf(e, 3, 1.6, 2.4), 8.4, -2.0, turn=3)
        put(g, mini_rocket(e), 5.8, 0.6)
        put(g, K.plant(2, 2), 5.8, -4.4)
        put(g, K.rug(e, 2.4, 2.0), 7.0, -2.6)
        put(g, K.poster(e, 3), 5.6, -2.0, turn=1)
        cx.light(7.0, 3.0, -1.8, rng=5.0)
        for k in range(2):
            ru = Room(5.2, 8.8, -5.0, 1.5, 3.2, y0=3.6 + 3.2 * k, upper=True)
            build_room(g, st, ru, roof=(k == 1), gable_axis="z")
        g.cur = UPPER
        top = K.roof_top(Room(5.2, 8.8, -5.0, 1.5, 3.2, y0=6.8), e)
        if e == 1:
            g.box(8.0, 8.2, 10.0, 13.0, -2.0, -1.8, C["crate_dk"])
            g.box(8.2, 9.0, 12.2, 12.8, -2.0, -1.9, C["fabric_r"])
        else:
            cx.shared(g, "dish_hq", 7.0, -3.4, y=top, name="CutUpperDish")
            g.box(6.0, 6.2, top, top + 3.0, -0.4, -0.2, C["grey_dk"])
            g.box(5.95, 6.25, top + 3.0, top + 3.3, -0.45, -0.15, C["red_glow"])
            if e == 5:
                put(g, K.dome(e, 1.2), 7.0, 0.0, y=top)
        g.cur = BASE


def workshop(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-8, 8, -7, 4, 6.5, shed=True)
        build_room(g, st, r, doors=[("pz", 0.0, 6.0, 5.2)])
        cx.shared(g, "rocket_h", 0.0, -2.8)
        put(g, K.engine_stand(e), -5.4, -1.0)
        put(g, K.workbench(e, 0), -5.0, -6.2)
        put(g, K.workbench(e, 1), 6.0, -6.2)
        put(g, K.workbench(e, 2), 1.4, -6.2)
        put(g, K.shelf(e, 0, 1.6, 2.4), -7.3, -3.6, turn=1)
        put(g, K.shelf(e, 1, 1.6, 2.4), -7.3, -1.6, turn=1)
        put(g, K.lockers(e, 4), 7.4, -2.6, turn=3)
        put(g, K.tool_cart(e, 0), 4.2, 0.0, turn=1)
        put(g, K.tool_cart(e, 1), -2.0, -6.1)
        for (x, z, y, v) in ((6.6, 2.9, 0.1, 0), (6.6, 2.0, 0.1, 1), (6.6, 2.9, 1.0, 2), (5.7, 2.9, 0.1, 3)):
            put(g, K.crate(v), x, z, y=y)
        put(g, K.barrel(0), -7.0, 3.0)
        put(g, K.barrel(1), -7.0, 2.2)
        put(g, K.barrel(2), -6.2, 3.0)
        put(g, K.pallet(1), -5.6, 1.6)
        put(g, K.poster(e, 0), -3.2, -6.6)
        put(g, K.poster(e, 1), 3.6, -6.6)
        put(g, emblem(e, 0.9), 0.0, -6.6, y=2.0)
        cx.shared(g, "tank_s", -5.0, -3.8)
        put(g, welding_cart(e), 3.6, -4.6, turn=3)
        hazard_box(g, -3.6, 3.6, -4.4, -1.2)
        lane(g, -3.2, 3.6, -1.0)
        lane(g, 3.2, 3.6, -1.0)
        cx.light(0.0, 5.0, -2.0, rng=10.0, energy=st["light_e"] * 1.3)
        cx.light(-5.0, 3.2, -4.5, rng=5.0)
        cx.light(5.0, 3.2, -4.5, rng=5.0)
        cx.light(0.0, 5.6, 5.2, "#ffd29a", 1.2, 6.0)
        # yard
        put(g, K.nose_cone(e), -7.0, 6.4, y=0.0)
        put(g, K.crate(0), 7.6, 6.2, y=0.0)
        put(g, K.crate(2), 8.4, 6.9, y=0.0)
        put(g, K.crate(1), 7.6, 6.2, y=0.9)
        put(g, K.cart(e), -4.8, 6.9, turn=0, y=0.0)
        put(g, K.lamp_post(e), -8.7, 4.8, turn=1, y=0.0)
        put(g, K.lamp_post(e), 8.7, 4.8, turn=3, y=0.0)
        cx.light(-8.3, 3.0, 4.8, "#ffd29a", 0.8, 5.0)
    elif lv == 2:
        r = Room(-12.8, -8.2, -7, 4, 12.0, shed=True)
        build_room(g, st, r, doors=[("pz", -10.5, 3.0, 8.0)], gable_axis="z", win_skip=("px",))
        cx.shared(g, "rocket_v", -10.5, -3.6)
        for y in (3.0, 6.0):
            ring_platform(g, st, -12.5, -8.5, -6.7, -1.9, y, -10.5, -3.6, 1.15)
        for y in np.arange(0.4, 9.0, 0.4):
            g.box(-12.5, -12.4, y, y + 0.1, -1.6, -1.0, C["hazard"])
        g.box(-12.5, -12.4, 0.1, 9.0, -1.7, -1.6, C["grey_dk"])
        g.box(-12.5, -12.4, 0.1, 9.0, -1.0, -0.9, C["grey_dk"])
        put(g, K.crate(1), -8.9, 3.2)
        put(g, K.barrel(3), -12.0, 3.2)
        cx.light(-10.5, 10.0, -3.0, rng=9.0)
        cx.light(-10.5, 4.6, -1.0, rng=5.0)
    else:
        r = Room(8.2, 12.8, -7, 3.0, 6.0, shed=True)
        build_room(g, st, r, doors=[("pz", 10.5, 3.0, 4.2)], gable_axis="z", win_skip=("nx",))
        cx.shared(g, "tank_m", 10.5, -4.4, turn=1)
        put(g, K.shelf(e, 4, 1.6, 2.4), 8.6, -0.8, turn=1)
        put(g, K.shelf(e, 5, 1.6, 2.4), 12.4, -0.8, turn=3)
        put(g, K.nose_cone(e), 12.0, 1.8)
        cx.light(10.5, 4.4, -2.0, rng=6.0)
        # gantry crane over the yard
        col = C["hazard"] if e != 5 else st["accent"]
        for x in (8.0, 12.6):
            for z in (5.0, 7.6):
                g.box(x, x + 0.3, 0.0, 6.4, z, z + 0.3, col)
            g.box(x - 0.1, x + 0.4, 0.0, 0.3, 4.8, 8.1, C["grey_dk"])
            g.box(x, x + 0.3, 3.0, 3.2, 5.0, 7.9, col)
        g.box(8.0, 12.9, 6.4, 6.8, 5.0, 5.3, col)
        g.box(8.0, 12.9, 6.4, 6.8, 7.6, 7.9, col)
        g.box(9.6, 10.4, 6.0, 6.4, 5.0, 7.9, C["ink"])
        g.box(9.95, 10.05, 3.4, 6.0, 6.4, 6.5, C["grey_dk"])
        g.box(9.7, 10.3, 3.1, 3.4, 6.2, 6.7, C["hazard"])
        put(g, K.crate(3, 1.0), 10.0, 6.45, y=2.0)
        g.box(12.6, 12.9, 6.8, 7.0, 5.0, 5.3, C["red_glow"])


def pad(g, st, lv, cx):
    e = st["era"]
    tower_col = {1: C["crate"], 2: C["grey"], 3: P_("#d9502f"), 4: st["metal_dk"], 5: st["metal"]}[e]
    if lv == 1:
        s, X, Y, Z = g.region(-5.5, 5.5, 0.0, 0.2, -5.5, 5.5)
        fx = np.floor(X * 10 + 1e-6).astype(np.int64)
        fz = np.floor(Z * 10 + 1e-6).astype(np.int64)
        col = np.where(((fx % 11) == 0) | ((fz % 11) == 0), C["concrete_dk"], C["concrete"])
        ring = (np.abs(X) > 5.1) | (np.abs(Z) > 5.1)
        stripe = (np.floor_divide(fx + fz + 1000, 4) % 2) == 0
        col = np.where(ring, np.where(stripe, C["hazard"], C["ink"]), col)
        g.col[s] = np.broadcast_to(col, g.col[s].shape)
        g.tag[s] = BASE
        g.clear(-1.0, 1.0, 0.1, 0.2, -5.5, -1.0)
        g.box(-1.0, 1.0, 0.0, 0.1, -5.5, -1.0, C["ink"])
        g.box(-1.1, 1.1, 0.2, 0.9, -1.1, 1.1, st["metal_dk"])
        s2, X2, Y2, Z2 = g.region(-1.1, 1.1, 0.2, 0.9, -1.1, 1.1)
        g.put_mask(s2, np.sqrt(X2 ** 2 + Z2 ** 2) < 0.6, 0)
        for (x, z) in ((-0.9, -0.9), (0.7, -0.9), (-0.9, 0.7), (0.7, 0.7)):
            g.box(x, x + 0.2, 0.9, 1.2, z, z + 0.2, C["hazard"])
        H = {1: 9.0, 2: 12.0, 3: 14.0, 4: 15.0, 5: 16.0}[e]
        lattice(g, -4.3, -2.9, -0.7, 0.7, 0.2, H, tower_col)
        g.box(-4.5, -2.7, H, H + 0.2, -0.9, 0.9, tower_col)
        g.box(-3.7, -3.5, H + 0.2, H + 1.6, -0.1, 0.1, C["grey_dk"])
        g.box(-3.8, -3.4, H + 1.6, H + 1.9, -0.2, 0.2, C["red_glow"])
        for y in (H * 0.45, H * 0.75):
            yy = round(y, 1)
            g.box(-2.9, -0.8, yy, yy + 0.3, -0.2, 0.2, tower_col)
            g.box(-1.0, -0.8, yy - 0.4, yy + 0.3, -0.3, 0.3, C["grey_dk"])
            g.box(-2.9, -1.0, yy - 0.2, yy - 0.1, -0.05, 0.05, C["yellow"])
        for y in np.arange(0.6, H, 0.4):   # stair zig-zag on the tower side
            g.box(-4.2, -3.0, round(y, 1), round(y, 1) + 0.1, 0.7, 0.9, C["grey_dk"])
        if e >= 4:
            g.box(-4.4, -2.8, H - 0.1, H, -0.8, 0.8, st["led"])
        # blockhouse with a small console room
        b = Room(5.6, 8.3, -8.3, -5.3, 2.8)
        build_room(g, st, b, doors=[("pz", 6.95, 1.6, 2.2)], roof_kind="parapet" if e <= 2 else None,
                   awning=False)
        put(g, K.console(e, 1.6, 2), 6.95, -7.6)
        cx.light(6.95, 2.2, -6.8, rng=3.5)
        # floodlights
        for (x, z) in ((5.0, 5.0), (-5.6, 3.6)):
            g.box(x, x + 0.2, 0.0, 6.0, z, z + 0.2, C["grey_dk"])
            g.box(x - 0.3, x + 0.5, 6.0, 6.5, z - 0.1, z + 0.3, C["ink"])
            g.box(x - 0.2, x + 0.4, 6.0, 6.4, z + 0.3, z + 0.4, C["warm_glow"])
        cx.light(4.0, 6.0, 4.0, "#ffd29a", 2.2, 14.0, shadow=True)
        put(g, K.cone(e), 4.5, 6.4, y=0.0)
        put(g, K.cone(e), 5.5, 6.6, y=0.0)
        put(g, K.barrel(2), -6.6, -2.0, y=0.0)
    elif lv == 2:
        cx.shared(g, "tank_m", -7.2, -4.0, turn=1, y=0.0)
        cx.shared(g, "tank_m", -7.2, 0.2, turn=1, y=0.0)
        g.box(-6.1, -4.3, 0.0, 0.3, -1.1, -0.8, C["grey_dk"])
        g.box(-6.1, -4.3, 0.0, 0.3, -2.2, -1.9, C["orange"])
        # water tower
        wx, wz = -6.4, 6.2
        for (dx, dz) in ((-0.8, -0.8), (0.6, -0.8), (-0.8, 0.6), (0.6, 0.6)):
            g.box(wx + dx, wx + dx + 0.2, 0.0, 6.5, wz + dz, wz + dz + 0.2, C["grey_dk"])
        g.box(wx - 0.8, wx + 0.8, 3.0, 3.1, wz - 0.8, wz + 0.8, C["grey_dk"])
        g.cyl_y(wx, wz, 1.3, 6.5, 8.6, st["wall"][0] if e >= 3 else C["grey_lt"])
        g.cyl_y(wx, wz, 1.35, 7.4, 7.7, C["orange"] if e != 5 else st["trim"])
        s, X, Y, Z = g.region(wx - 1.4, wx + 1.4, 8.6, 9.6, wz - 1.4, wz + 1.4)
        g.put_mask(s, np.sqrt((X - wx) ** 2 + (Z - wz) ** 2) < 1.3 - (Y - 8.6) * 1.2, st["roof"][0])
        for x in np.arange(-8.0, 4.6, 1.0):
            g.box(x, x + 0.1, 0.0, 1.4, -8.2, -8.1, st["metal_dk"])
        g.box(-8.0, 4.6, 1.3, 1.4, -8.2, -8.1, st["metal_dk"])
        g.box(-8.0, 4.6, 0.6, 0.7, -8.2, -8.1, st["metal"])
    else:
        for (mx, mz) in ((8.0, 6.8), (-6.6, -7.0), (8.0, -3.0)):
            lattice(g, mx - 0.3, mx + 0.3, mz - 0.3, mz + 0.3, 0.0, 15.0, C["grey"], step=1.0)
            g.box(mx - 0.05, mx + 0.05, 15.0, 17.0, mz - 0.05, mz + 0.05, C["grey_dk"])
            g.box(mx - 0.15, mx + 0.15, 15.0, 15.3, mz - 0.15, mz + 0.15, C["red_glow"])
        H = {1: 9.0, 2: 12.0, 3: 14.0, 4: 15.0, 5: 16.0}[e]
        # hammerhead crane on the tower top
        g.box(-3.7, -3.5, H + 0.2, H + 3.0, -0.1, 0.1, tower_col)
        g.box(-6.0, 0.6, H + 3.0, H + 3.3, -0.2, 0.2, tower_col)
        g.box(-6.0, -5.0, H + 2.2, H + 3.0, -0.4, 0.4, C["grey_dk"])
        g.box(0.2, 0.3, H + 1.0, H + 3.0, -0.05, 0.05, C["grey_dk"])


def lab(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-5.5, 5.5, -5.0, 3.5, 3.8)
        build_room(g, st, r, doors=[("pz", -1.0, 2.2, 2.6)])
        put(g, K.fume_hood(e), -4.2, -4.3)
        put(g, K.lab_bench(e, 0), -2.0, -4.2)
        put(g, K.lab_bench(e, 3), 0.6, -4.2)
        put(g, K.shelf(e, 6, 1.6, 2.2), 2.9, -4.4)
        put(g, K.server_rack(e, 1), 4.6, -4.3)
        put(g, K.lab_bench(e, 1), 2.6, -1.4, turn=2)
        put(g, K.lab_bench(e, 4), 2.6, -0.4)
        put(g, K.desk(e, True, 1), -3.8, -1.0)
        put(g, K.whiteboard(e, 1, 2.2), -5.0, 0.8, turn=1)
        put(g, K.plant(1, 0), -4.8, 2.6)
        put(g, K.plant(2, 3), 4.8, 2.6)
        put(g, K.poster(e, 1), 5.0, -1.0, turn=3)
        cx.light(-2.0, 3.0, -1.6, rng=6.0)
        cx.light(2.6, 3.0, -1.0, rng=6.0)
        cx.light(-1.0, 2.3, 4.0, "#ffd29a", 1.0, 4.5)
        # yard
        put(g, K.gas_cage(e), 3.6, 4.4, turn=2, y=0.0)
        put(g, K.planter(e, 1.6, 0.8, 1), -3.6, 4.1, y=0.0)
        put(g, K.bench(e), 1.4, 5.4, turn=2, y=0.0)
        put(g, K.lamp_post(e), -5.4, 4.6, turn=1, y=0.0)
        put(g, K.shelf(e, 5, 1.6, 2.0), 5.0, 1.3, turn=3)
        put(g, K.plant(0, 1), -3.4, -1.5, y=0.9)
        put(g, K.rug(e, 2.0, 1.4), -3.8, -0.6)
        put(g, K.floor_lamp(e), -4.9, -2.6)
        hazard_box(g, -5.1, -3.3, -3.7, -3.5)
    elif lv == 2:
        r = Room(-9.8, -5.8, -4.0, 2.5, 3.4)
        build_room(g, st, r, doors=[("pz", -7.8, 2.0, 2.5)], roof=False)
        g.box(-9.8, -5.8, 3.4, 3.6, -4.0, 2.5, st["roof"][0] if e != 1 else C["crate_dk"], ROOF)
        cx.shared(g, "obs_dome5" if e == 5 else "obs_dome", -7.8, -0.75, y=3.6, name="CutRoofDome")
        cx.shared(g, "telescope", -7.8, -1.8)
        put(g, K.shelf(e, 7, 1.4, 1.6), -9.4, 0.6, turn=1)
        put(g, K.desk(e, True, 0), -6.4, -3.4, turn=3)
        cx.light(-7.8, 3.0, -0.8, "#bfe8ff" if e > 2 else None, rng=5.0)
    else:
        r = Room(5.8, 9.8, -5.0, 2.5, 3.8)
        build_room(g, st, r, doors=[("pz", 7.8, 2.0, 2.6)], roof=False)
        put(g, K.vacuum_chamber(e), 7.8, -2.9)
        put(g, K.server_rack(e, 2), 9.3, 1.6, turn=3)
        put(g, K.plant(0, 2), 6.3, 1.9)
        cx.light(7.8, 3.0, -1.0, "#d6ecff", rng=5.0)
        ru = Room(5.8, 9.8, -5.0, 2.5, 3.2, y0=3.8, upper=True)
        build_room(g, st, ru)
        g.cur = UPPER
        top = K.roof_top(ru, e)
        g.box(9.0, 9.2, top, top + 3.0, -4.4, -4.2, C["grey_dk"])
        g.box(8.6, 9.6, top + 2.6, top + 2.7, -4.35, -4.25, C["grey_dk"])
        g.box(8.6, 8.8, top + 2.4, top + 2.8, -4.4, -4.2, C["white"])
        g.box(9.4, 9.6, top + 2.4, top + 2.8, -4.4, -4.2, C["white"])
        g.box(9.0, 9.2, top + 3.0, top + 3.2, -4.4, -4.2, C["red_glow"])
        g.cur = BASE


def control(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-4.6, 6.0, -4.5, 3.0, 4.2)
        build_room(g, st, r, doors=[("pz", 4.4, 2.2, 2.6)], reserved=[(2.6, 4.2, -2.8, -1.2)])
        put(g, K.big_screen(e, 5.4, 2.2, 0), -1.5, -4.0)
        put(g, K.clock_row(e, 3), -1.5, -4.1, y=3.5)
        put(g, K.console(e, 2.4, 3), -2.8, -1.8)
        put(g, K.console(e, 2.4, 3), -0.2, -1.8)
        put(g, K.console(e, 2.4, 2), -2.8, 0.6)
        put(g, K.desk(e, True, 2), 3.6, -3.4)
        put(g, K.server_rack(e, 0), 5.4, -3.2, turn=3)
        put(g, K.server_rack(e, 3), 5.4, -2.3, turn=3)
        put(g, K.coffee_corner(e), 5.2, 0.5, turn=3)
        put(g, K.plant(1, 1), -4.0, 2.3)
        put(g, K.plant(2, 2), 2.2, -3.9)
        cx.light(-1.5, 3.4, -1.4, "#bfe8ff" if e > 2 else None, rng=7.0)
        cx.light(3.8, 3.4, -1.0, rng=5.0)
        cx.light(4.4, 2.3, 3.6, "#ffd29a", 1.0, 4.5)
        put(g, K.planter(e, 2.4, 0.8, 0), 0.6, 3.6, y=0.0)
        put(g, K.bike(e, 2), -2.4, 4.0, y=0.0)
        g.cur = ROOF
        top = K.roof_top(r, e)
        cx.shared(g, "dish_s", 3.4, -2.0, y=top, name="CutRoofDish")
        g.cur = BASE
        put(g, K.rug(e, 2.6, 2.0), 3.6, -2.8)
        put(g, K.plant(1, 3), -4.0, -3.9)
    elif lv == 2:
        r = Room(-7.8, -4.9, -4.0, 2.0, 3.6)
        build_room(g, st, r, doors=[("pz", -6.35, 1.8, 2.5)], gable_axis="z", awning=False)
        put(g, K.radio_desk(e), -6.35, -3.3)
        put(g, K.server_rack(e, 4), -7.3, -0.9, turn=1)
        put(g, K.poster(e, 0), -5.2, -1.2, turn=3)
        cx.light(-6.35, 2.8, -1.4, rng=4.5)
    else:
        mx, mz = 7.0, -4.2
        lattice(g, mx - 0.5, mx + 0.5, mz - 0.5, mz + 0.5, 0.0, 14.0, C["grey_lt"] if e != 4 else st["metal"])
        for y in (9.0, 11.0, 13.0):
            g.box(mx - 1.5, mx + 1.5, y, y + 0.1, mz - 0.05, mz + 0.05, C["grey_dk"])
            for x in np.arange(mx - 1.4, mx + 1.5, 0.5):
                g.box(x, x + 0.1, y - 0.2, y + 0.3, mz - 0.05, mz + 0.05, C["grey_dk"])
        g.box(mx - 0.15, mx + 0.15, 14.0, 14.3, mz - 0.15, mz + 0.15, C["red_glow"])
        put(g, K.ac_unit(e), 7.0, -0.8, turn=3, y=0.0)
        put(g, K.ac_unit(e), 7.0, 0.6, turn=3, y=0.0)
        cx.shared(g, "dish_m", -6.4, -5.0, y=0.0)


def antenna(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-6.8, -2.6, 0.8, 5.0, 3.0)
        build_room(g, st, r, doors=[("pz", -4.7, 1.8, 2.3)], gable_axis="z", awning=False)
        put(g, K.radio_desk(e), -4.7, 1.6)
        put(g, K.shelf(e, 8, 1.2, 1.6), -6.3, 3.6, turn=1)
        put(g, K.plant(0, 0), -3.1, 4.4)
        cx.light(-4.7, 2.4, 3.0, rng=4.0)
        cx.shared(g, "dish_l", 4.0, 0.6, y=0.0)
        g.box(-2.6, 4.0, 0.0, 0.2, 2.4, 2.6, C["grey_dk"])
        put(g, K.lamp_post(e), 6.8, 7.0, turn=3, y=0.0)
        put(g, K.planter(e, 1.6, 0.6, 1), -6.0, 5.6, y=0.0)
    elif lv == 2:
        cx.shared(g, "dish_xl", -2.6, -3.6, y=0.0)
        g.box(-2.7, -2.5, 0.0, 0.2, -1.0, 0.8, C["grey_dk"])
        put(g, K.server_rack(e, 1), 1.6, -1.4, turn=0, y=0.0)
        put(g, K.server_rack(e, 2), 2.4, -1.4, turn=0, y=0.0)
        g.box(1.0, 3.0, 2.2, 2.4, -2.0, -0.8, C["grey_dk"])
    else:
        cx.shared(g, "dish_n", 4.6, -4.4, y=0.0)
        cx.shared(g, "dish_n2", 2.6, 5.0, y=0.0)
        put(g, K.fence(e, 4.0), 5.0, -6.9, y=0.0)
        put(g, K.fence(e, 4.0), -5.2, -6.9, y=0.0)


def training(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-4.2, 4.2, -5.6, 2.2, 4.0)
        build_room(g, st, r, doors=[("pz", 0.0, 2.4, 2.6)])
        put(g, K.climbing_wall(e, 3.0), -2.2, -5.1)
        put(g, K.weight_rack(e), 2.4, -4.9)
        put(g, K.treadmill(e), -3.2, -1.4)
        put(g, K.treadmill(e), -3.2, -3.4)
        put(g, exercise_bike(e), 1.2, -4.8)
        put(g, K.gym_mat(e, 1.0, 2.0, 2), 3.4, 0.0)
        put(g, helmet_stand(e), -0.9, -4.9)
        put(g, K.gym_mat(e, 2.4, 1.6, 0), 0.4, -2.4)
        put(g, K.gym_mat(e, 1.2, 1.2, 1), -1.0, -0.6)
        put(g, K.punching_bag(e), 2.6, 0.6)
        put(g, K.lockers(e, 4), 3.7, -2.0, turn=3)
        put(g, K.poster(e, 2), -3.9, 1.0, turn=1)
        put(g, K.water_cooler(e), -3.6, 1.5)
        cx.light(0.0, 3.4, -1.6, rng=6.5)
        cx.light(0.0, 2.3, 3.2, "#ffd29a", 1.0, 4.5)
        put(g, K.cone(e), -2.4, 4.0, y=0.0)
        put(g, K.cone(e), -3.4, 4.6, y=0.0)
        put(g, K.cone(e), -2.4, 5.2, y=0.0)
        put(g, K.planter(e, 1.4, 0.8, 2), 2.6, 3.0, y=0.0)
        put(g, K.bench(e), -2.8, 1.5, turn=2)
        put(g, K.plant(1, 0), 3.6, 1.6)
    elif lv == 2:
        # running track on the right side + bleachers
        s, X, Y, Z = g.region(4.6, 7.9, 0.0, 0.1, -6.2, 6.2)
        cxp, R0, R1 = 6.25, 0.8, 1.6
        dz = np.maximum(np.abs(Z) - 4.4, 0.0)
        d = np.sqrt((X - cxp) ** 2 + dz ** 2)
        track = (d >= R0) & (d <= R1)
        lane = track & (np.abs(d - 1.2) < 0.05)
        g.put_mask(s, track, P_("#b5523f"))
        g.put_mask(s, lane, C["white"])
        g.put_mask(s, (d < R0) & ~track, C["leaf2"])
        put(g, K.bench(e), 6.25, -0.2, turn=1, y=0.0)
        put(g, K.lamp_post(e), 7.6, -6.0, turn=3, y=0.0)
    else:
        r = Room(-7.9, -4.5, -5.6, 2.2, 4.0)
        build_room(g, st, r, doors=[("pz", -6.2, 1.8, 2.6)], gable_axis="z")
        put(g, centrifuge(e), -6.2, -3.2, turn=1)
        put(g, sim_capsule(e), -6.6, -0.6)
        cx.light(-6.2, 3.2, -1.6, rng=5.0)


def factory(g, st, lv, cx):
    e = st["era"]
    if lv == 1:
        r = Room(-7.0, 7.0, -5.6, 3.2, 6.0, shed=True)
        build_room(g, st, r, doors=[("pz", 3.2, 4.0, 4.0), ("pz", -3.6, 1.8, 2.5)],
                   roof_kind="sawtooth" if e in (2, 3, 4) else None)
        put(g, K.conveyor(e, 9.0, 0), -1.4, -1.6)
        if e >= 3:
            put(g, K.robot_arm(e), -4.2, -3.2)
            put(g, K.robot_arm(e), 0.4, -3.2)
        else:
            put(g, K.workbench(e, 3), -4.2, -3.4, turn=0)
        put(g, K.workbench(e, 4), 1.2, -5.0)
        put(g, K.shelf(e, 9, 1.6, 2.4), -5.4, -5.0)
        put(g, K.shelf(e, 2, 1.6, 2.4), -3.6, -5.0)
        put(g, K.forklift(e), 5.4, -3.4)
        put(g, K.pallet(0), 5.8, -0.4)
        put(g, K.pallet(2), 4.4, -1.2)
        put(g, K.barrel(1), -6.2, 2.5)
        put(g, K.barrel(3), -6.2, 1.7)
        put(g, emblem(e, 0.8), -1.2, -5.2, y=2.4)
        hazard_box(g, -6.1, 3.3, -2.4, -0.8)
        lane(g, 1.4, 2.9, 0.0)
        lane(g, 5.0, 2.9, 0.0)
        put(g, K.crate(1), -6.0, -2.8)
        put(g, K.crate(3), -6.0, -2.8, y=0.9)
        cx.light(-1.4, 4.6, -1.6, rng=9.0, energy=st["light_e"] * 1.2)
        cx.light(4.6, 3.6, -2.0, rng=5.0)
        cx.light(3.2, 4.6, 4.2, "#ffd29a", 1.0, 5.0)
        put(g, K.pallet(1), 6.4, 4.6, y=0.0)
        put(g, K.pallet(0), -6.2, 4.4, y=0.0)
        put(g, K.lamp_post(e), -1.0, 4.4, turn=3, y=0.0)
    elif lv == 2:
        for z in (-4.2, -1.4, 1.4):
            put(g, silo(e, 1.2, 7.0), -9.2, z, turn=1, y=0.0)
        g.box(-9.4, -7.0, 5.0, 5.3, -1.6, -1.2, C["grey_dk"])
        g.box(-9.4, -9.0, 5.0, 5.3, -4.2, 1.4, C["grey_dk"])
        g.box(-8.0, -7.6, 0.0, 5.0, -1.6, -1.2, C["grey_dk"])
        put(g, K.barrel(0), -7.6, 3.6, y=0.0)
    else:
        r = Room(7.4, 10.8, -5.6, 2.2, 5.0)
        build_room(g, st, r, doors=[("pz", 9.1, 2.4, 3.6)], gable_axis="z", win_skip=("nx",))
        cx.shared(g, "tank_f", 9.1, -3.4, turn=1)
        put(g, K.tool_cart(e, 2), 10.2, 0.4, turn=3)
        cx.light(9.1, 3.6, -1.8, rng=5.0)
        g.box(7.0, 7.4, 3.6, 3.8, -3.0, -2.4, C["grey_dk"])


RECIPES = {"hq": hq, "workshop": workshop, "pad": pad, "lab": lab, "control": control, "antenna": antenna,
           "training": training, "factory": factory}

# Walk spots: (name, (x, z), action, facing (rotation.y), level, doorway) where doorway is
# (x of the doorway centre, z of the outer wall face) for interior spots, None outside.
FACE_BACK = math.pi       # looking towards -z (the back wall)
SPOTS = {
    "hq": [("Reception", (0.0, -2.3), "talk", FACE_BACK, 1, (0.0, 3.0)),
           ("Desk", (-1.9, 1.3), "work_scan", FACE_BACK, 1, (0.0, 3.0)),
           ("Coffee", (3.2, -3.2), "idle", FACE_BACK, 1, (0.0, 3.0)),
           ("Yard", (-2.4, 5.8), "clipboard", FACE_BACK, 1, None),
           ("Meeting", (-7.0, 0.6), "talk", FACE_BACK, 2, (-7.0, 2.5)),
           ("Director", (7.0, -1.9), "clipboard", FACE_BACK, 3, (7.0, 1.5))],
    "workshop": [("Stage", (0.0, -0.8), "work_hammer", FACE_BACK, 1, (0.0, 4.0)),
                 ("Engine", (-5.0, 0.4), "work_scan", FACE_BACK, 1, (0.0, 4.0)),
                 ("Bench", (6.0, -5.0), "work_hammer", FACE_BACK, 1, (0.0, 4.0)),
                 ("Crates", (7.6, 7.4), "carry", FACE_BACK, 1, None),
                 ("HighBay", (-10.5, -1.0), "look_up", FACE_BACK, 2, (-10.5, 4.0)),
                 ("Store", (10.5, -1.4), "carry", FACE_BACK, 3, (10.5, 3.0))],
    "pad": [("Edge", (3.2, 6.6), "look_up", FACE_BACK, 1, None),
            ("Tower", (-3.6, 2.0), "clipboard", FACE_BACK, 1, None),
            ("Bunker", (6.95, -6.6), "work_scan", FACE_BACK, 1, (6.95, -5.3))],
    "lab": [("Bench", (-2.0, -3.0), "work_scan", FACE_BACK, 1, (-1.0, 3.5)),
            ("Island", (2.6, 0.7), "work_scan", FACE_BACK, 1, (-1.0, 3.5)),
            ("Yard", (0.0, 5.6), "clipboard", FACE_BACK, 1, None),
            ("Telescope", (-7.8, 0.8), "look_up", FACE_BACK, 2, (-7.8, 2.5)),
            ("Chamber", (7.8, 0.6), "work_scan", FACE_BACK, 3, (7.8, 2.5))],
    "control": [("Console", (-0.2, -0.8), "work_scan", FACE_BACK, 1, (4.4, 3.0)),
                ("Console2", (-2.8, -0.8), "work_scan", FACE_BACK, 1, (4.4, 3.0)),
                ("Console3", (-2.8, 1.6), "work_scan", FACE_BACK, 1, (4.4, 3.0)),
                ("Radio", (-6.35, -2.1), "work_scan", FACE_BACK, 2, (-6.35, 2.0))],
    "antenna": [("Hut", (-4.7, 2.8), "work_scan", FACE_BACK, 1, (-4.7, 5.0)),
                ("Dish", (5.8, 3.4), "look_up", FACE_BACK, 1, None),
                ("BigDish", (-1.4, 0.9), "look_up", FACE_BACK, 2, None)],
    "training": [("Climb", (-2.2, -3.8), "look_up", FACE_BACK, 1, (0.0, 2.2)),
                 ("Weights", (2.4, -3.6), "work_hammer", FACE_BACK, 1, (0.0, 2.2)),
                 ("Mat", (0.4, -1.6), "dance", FACE_BACK, 1, (0.0, 2.2)),
                 ("Track", (6.25, 3.8), "dance", 0.0, 2, None),
                 ("Centrifuge", (-6.2, 0.9), "look_up", FACE_BACK, 3, (-6.2, 2.2))],
    "factory": [("Line", (-2.6, -0.4), "work_hammer", FACE_BACK, 1, (-3.6, 3.2)),
                ("Pallets", (4.4, 0.2), "carry", FACE_BACK, 1, (3.2, 3.2)),
                ("Silos", (-7.6, 4.8), "clipboard", FACE_BACK, 2, None),
                ("Tanks", (9.1, -1.2), "work_hammer", FACE_BACK, 3, (9.1, 2.2))],
}

# construction scaffold: centre x, z, size x, z, height
SCAFFOLD = {"hq": (0, -1, 11, 9, 5.0), "workshop": (0, -1.5, 17, 12, 8.0), "pad": (0, 0, 11, 11, 6.0),
            "lab": (0, -0.75, 12, 9.5, 5.0), "control": (0.7, -0.75, 11.6, 8.5, 5.4),
            "antenna": (-2, 0, 10, 10, 4.0), "training": (0, -1.7, 9.4, 8.8, 5.0),
            "factory": (0, -1.2, 15, 9.8, 7.0)}


# ------------------------------------------------------------------ scaffold & rocket models
def scaffold(kind):
    cx_, cz_, sx, sz, h = SCAFFOLD[kind]
    w, d = LOT_SIZE[kind]
    g = Grid(-w / 2 - 1, w / 2 + 1, h + 9, -d / 2 - 1, d / 2 + 1.5)
    x0, x1, z0, z1 = cx_ - sx / 2, cx_ + sx / 2, cz_ - sz / 2, cz_ + sz / 2
    pole, plank, brace = P_("#d9a92b"), P_("#b88a4e"), P_("#9aa3b0")
    # foundation slab being poured
    g.box(x0 + 0.4, x1 - 0.4, 0.0, 0.2, z0 + 0.4, z1 - 0.4, C["concrete"])
    s, X, Y, Z = g.region(x0 + 0.4, x1 - 0.4, 0.2, 0.3, z0 + 0.4, z1 - 0.4)
    g.put_mask(s, ((np.floor(X * 10 + 1e-6) % 8 == 0) | (np.floor(Z * 10 + 1e-6) % 8 == 0)), C["grey_dk"])
    # rebar starters and half-built walls in the era-neutral block colour
    for (a0, a1, b0, b1) in ((x0 + 0.6, x1 - 0.6, z0 + 0.6, z0 + 0.9), (x0 + 0.6, x0 + 0.9, z0 + 0.6, z1 - 0.6)):
        g.box(a0, a1, 0.2, 1.6, b0, b1, P_("#a9b0ba"))
        s, X, Y, Z = g.region(a0, a1, 0.2, 1.6, b0, b1)
        g.put_mask(s, (np.floor((Y) * 10 + 1e-6) % 3 == 0), P_("#8d949e"), only_filled=True)
        s, X, Y, Z = g.region(a0, a1, 1.6, 2.2, b0, b1)
        g.put_mask(s, ((np.floor(X * 10 + 1e-6) + np.floor(Z * 10 + 1e-6)) % 6 == 0), C["grey_dk"])
    # scaffold: poles every ~2 m on the front and right faces, planks every 2 m
    xs = np.arange(x0, x1 + 0.01, max(1.8, sx / max(1, round(sx / 2.0))))
    zs = np.arange(z0, z1 + 0.01, max(1.8, sz / max(1, round(sz / 2.0))))
    for x in xs:
        for z in (z1, z1 + 1.0):
            g.box(x, x + 0.1, 0.0, h + 1.0, z, z + 0.1, pole)
    for z in zs:
        for x in (x1, x1 + 1.0):
            g.box(x, x + 0.1, 0.0, h + 1.0, z, z + 0.1, pole)
    for y in np.arange(2.0, h + 0.5, 2.0):
        g.box(x0, x1 + 1.1, y, y + 0.1, z1, z1 + 1.1, plank)
        g.box(x1, x1 + 1.1, y, y + 0.1, z0, z1 + 1.1, plank)
        g.box(x0, x1 + 1.1, y + 1.0, y + 1.1, z1 + 1.0, z1 + 1.1, pole)
        g.box(x1 + 1.0, x1 + 1.1, y + 1.0, y + 1.1, z0, z1 + 1.1, pole)
    # diagonal braces on the front
    for i, x in enumerate(xs[:-1]):
        n = 20
        for k in range(n):
            xx = x + (xs[i + 1] - x) * k / n
            yy = 0.2 + 1.8 * (k / n if i % 2 == 0 else 1 - k / n)
            g.box(round(xx, 1), round(xx, 1) + 0.1, round(yy, 1), round(yy, 1) + 0.1, z1 + 1.0, z1 + 1.1, brace)
    # tarp with stripes on the left half
    s, X, Y, Z = g.region(x0, cx_, 0.6, h * 0.8, z1 + 1.2, z1 + 1.3)
    tarp = np.where(np.floor(X * 10 + 1e-6) % 12 < 9, P_("#3f6f9a"), P_("#2e5579"))
    g.col[s] = np.broadcast_to(tarp, g.col[s].shape)
    g.tag[s] = BASE
    # tower crane at the back-left corner
    tx, tz = x0 - 0.6, z0 - 0.6
    lattice(g, tx - 0.5, tx + 0.5, tz - 0.5, tz + 0.5, 0.0, h + 6.0, C["hazard"], step=1.0)
    g.box(tx - 2.6, tx + sx * 0.75, h + 6.0, h + 6.6, tz - 0.3, tz + 0.3, C["hazard"])
    g.box(tx - 2.6, tx - 1.0, h + 4.8, h + 6.0, tz - 0.6, tz + 0.6, C["grey_dk"])
    g.box(tx - 0.6, tx + 0.6, h + 6.6, h + 7.4, tz - 0.6, tz + 0.6, C["ink"])
    g.box(tx - 0.5, tx + 0.5, h + 6.8, h + 7.2, tz + 0.6, tz + 0.7, C["ice_glow"])
    hx = tx + sx * 0.55
    g.box(hx, hx + 0.1, h + 2.0, h + 6.0, tz - 0.05, tz + 0.05, C["grey_dk"])
    g.box(hx - 0.3, hx + 0.4, h + 1.6, h + 2.0, tz - 0.3, tz + 0.3, C["hazard"])
    put(g, K.pallet(0), hx + 0.05, tz, y=h + 0.4)
    g.box(tx + sx * 0.75 - 0.2, tx + sx * 0.75, h + 6.6, h + 6.9, tz - 0.1, tz + 0.1, C["red_glow"])
    # yard: bricks, sand, mixer, cones, a barrier and the site hut
    put(g, K.pallet(2), x1 + 2.2, z0 + 1.2, y=0.0)
    put(g, K.pallet(1), x1 + 2.2, z0 + 2.6, y=0.0)
    g.box(x0 + 0.8, x0 + 2.0, 0.0, 0.6, z1 + 2.0, z1 + 2.8, C["brick_pile"])
    s, X, Y, Z = g.region(x1 - 3.0, x1 - 1.0, 0.0, 0.8, z1 + 1.8, z1 + 3.0)
    g.put_mask(s, (Y < 0.8 - np.abs(X - (x1 - 2.0)) * 0.6 - np.abs(Z - (z1 + 2.4)) * 0.6), C["sand"])
    for i, x in enumerate(np.arange(x0, x1, 1.4)):
        put(g, K.cone(1), x, z1 + 3.4, y=0.0)
    mx_, mz_ = x1 + 2.0, z1 + 2.2
    g.box(mx_ - 0.6, mx_ + 0.6, 0.0, 0.3, mz_ - 0.4, mz_ + 0.4, C["grey_dk"])
    s, X, Y, Z = g.region(mx_ - 0.6, mx_ + 0.6, 0.3, 1.4, mz_ - 0.6, mz_ + 0.6)
    g.put_mask(s, ((X - mx_) ** 2 + (Y - 0.85) ** 2 + ((Z - mz_) * 1.3) ** 2) < 0.3, C["orange"])
    return g


def rocket(era):
    g = Grid(-2.0, 2.0, 22.0, -2.0, 2.0)
    r, h = {1: (0.35, 6.0), 2: (0.5, 9.0), 3: (0.7, 12.0), 4: (0.8, 14.0), 5: (0.9, 16.0)}[era]
    st = STYLES[era]
    body = C["rocket"]
    band = {1: C["orange"], 2: C["red"], 3: C["orange"], 4: P_("#3fe0c5", 1.4), 5: P_("#a08cff", 1.6)}[era]
    g.cyl_y(0, 0, r, 0.3, h, body)
    for y in (h * 0.3, h * 0.62):
        g.cyl_y(0, 0, r + 0.02, y, y + 0.3, band)
    if era in (2, 3):   # roll pattern
        s, X, Y, Z = g.region(-r - 0.1, r + 0.1, h * 0.75, h * 0.9, -r - 0.1, r + 0.1)
        g.put_mask(s, (np.arctan2(Z, X) % (math.pi / 2) < math.pi / 4) & (Y > 0), C["ink"], only_filled=True)
    if era >= 4:
        s, X, Y, Z = g.region(-r - 0.1, r + 0.1, 0.3, h * 0.28, -r - 0.1, r + 0.1)
        g.put_mask(s, np.ones((1, 1, 1), bool), C["ink"] if era == 4 else st["metal"], only_filled=True)
    # nose / capsule
    nh = r * 3.0
    s, X, Y, Z = g.region(-r, r, h, h + nh, -r, r)
    yy = (Y - h) / nh
    g.put_mask(s, np.sqrt(X ** 2 + Z ** 2) <= r * np.sqrt(np.clip(1 - yy, 0, 1)) + 0.02,
               C["orange"] if era < 5 else C["white"])
    if era == 5:
        g.box(-0.05, 0.05, h + nh, h + nh + 1.2, -0.05, 0.05, C["grey_dk"])
        g.cyl_y(0, 0, r + 0.02, h - 0.4, h, C["ink"])
        g.box(-0.2, 0.2, h - 0.3, h - 0.1, r - 0.05, r + 0.05, C["ice_glow"])
    # engine and fins
    g.cyl_y(0, 0, r * 0.6, 0.0, 0.3, C["nozzle"])
    fin = C["orange_dk"] if era != 4 else C["ink"]
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        fx, fz = math.cos(ang), math.sin(ang)
        span = r * 1.4 + 0.3
        for k in range(int(span * 10)):
            rr = r + k * 0.1
            top = 0.3 + (1.8 if era > 1 else 1.4) * (1 - k / (span * 10)) + 0.4
            g.box(fx * rr - 0.05, fx * rr + 0.05, 0.1, round(top, 1), fz * rr - 0.05, fz * rr + 0.05, fin)
    if era == 3 or era == 5:  # side boosters
        for side in (-1, 1):
            bx = side * (r + 0.4)
            g.cyl_y(bx, 0, 0.35, 0.3, h * 0.5, C["white"])
            s, X, Y, Z = g.region(bx - 0.4, bx + 0.4, h * 0.5, h * 0.5 + 1.0, -0.4, 0.4)
            g.put_mask(s, np.sqrt((X - bx) ** 2 + Z ** 2) <= 0.35 * (1 - (Y - h * 0.5) / 1.0) + 0.02, C["orange"])
            g.cyl_y(bx, 0, 0.2, 0.0, 0.3, C["nozzle"])
    return g


# ------------------------------------------------------------------ export
def export(g, path):
    m = cv.mesh_grid(g)
    nodes = []
    for t in (BASE, cv.ROOF, cv.CUT_PX, cv.CUT_NX, cv.CUT_PZ, cv.CUT_NZ, UPPER):
        if t in m:
            pos, nrm, col, idx, org = m[t]
            nodes.append((cv.PIECE_NAME[t], (pos, nrm, col, idx), org))
    path.parent.mkdir(parents=True, exist_ok=True)
    cv.write_glb(path, nodes)
    rel = path.relative_to(ROOT).as_posix()
    cv.write_import(path, "res://" + rel, MAT)
    return sum(len(n[1][3]) // 3 for n in nodes)


def door_marker(spot_xz, doorway):
    """road-side door point: straight out from the doorway (or from the spot outside)"""
    sx, sz = spot_xz
    if doorway is None:
        return (sx, DOOR_Z)
    return (doorway[0], DOOR_Z)


def via_point(doorway):
    """a point just inside the doorway: door marker -> via -> spot"""
    return None if doorway is None else (doorway[0], round(doorway[1] - 1.1, 2))


def check_paths(kind, union_occ, grid):
    """prints spots whose walking legs cut through voxels (between 0.3 m and 1.4 m)"""
    bad = []
    for (name, (sx, sz), action, yaw, lv, doorway) in SPOTS[kind]:
        pts = [door_marker((sx, sz), doorway)]
        if doorway is not None:
            pts.append(via_point(doorway))
        pts.append((sx, sz))
        hits = 0
        for (ax, az), (bx, bz) in zip(pts[:-1], pts[1:]):
            L = math.hypot(bx - ax, bz - az) or 1
            for t in np.linspace(0.0, 1.0, 100):
                for off in (-0.3, 0.0, 0.3):
                    x = ax + (bx - ax) * t + off * (bz - az) / L
                    z = az + (bz - az) * t - off * (bx - ax) / L
                    i = cv.m2v(x) - grid.min[0]
                    k = cv.m2v(z) - grid.min[2]
                    if 0 <= i < grid.nx and 0 <= k < grid.nz and union_occ[i, 3:14, k].any():
                        hits += 1
        if hits:
            bad.append(f"{name}({hits})")
    return bad


_WRITTEN = set()


def build_kind(kind, eras=(1, 2, 3, 4, 5)):
    w, d = LOT_SIZE[kind]
    info = {"lights": {}, "tris": 0}
    paths_bad = None
    for era in eras:
        st = STYLES[era]
        union = None
        for lv in (1, 2, 3):
            g = Grid(-w / 2 - 1, w / 2 + 1, HEIGHT[kind], -d / 2 - 1, d / 2 + 1.5)
            cx = Ctx(st)
            RECIPES[kind](g, st, lv, cx)
            info["lights"][(era, lv)] = cx.lights
            info.setdefault("props", {})[(era, lv)] = cx.props
            for (key, *_r) in cx.props:
                if key not in _WRITTEN:
                    pg = Grid(-5, 5, 12, -5, 5)
                    pg.stamp(SHARED[key](), 0, 0, 0, 0)
                    info["tris"] += export(pg, ASSETS / "props" / f"{key}.glb")
                    _WRITTEN.add(key)
            info["tris"] += export(g, ASSETS / kind / f"{kind}_e{era}_l{lv}.glb")
            occ = g.col > 0
            union = occ if union is None else (union | occ)
            last = g
        if era == 3:
            paths_bad = check_paths(kind, union, last)
    if paths_bad:
        print(f"  ! {kind}: walking legs clip props: {', '.join(paths_bad)}")
    info["tris"] += export(scaffold(kind), ASSETS / kind / f"{kind}_scaffold.glb")
    if kind == "pad":
        for era in eras:
            info["tris"] += export(rocket(era), ASSETS / "pad" / f"rocket_e{era}.glb")
    return info


# ------------------------------------------------------------------ scenes
def hexc(h):
    h = h.lstrip("#")
    return "Color(%.4f, %.4f, %.4f, 1)" % tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def tf(x, y, z, yaw=0.0):
    c, s = math.cos(yaw), math.sin(yaw)
    # rows of a rotation about Y by `yaw` (Godot text format lists the basis by rows)
    return f"Transform3D({c:.5f}, 0, {s:.5f}, 0, 1, 0, {-s:.5f}, 0, {c:.5f}, {x:.3f}, {y:.3f}, {z:.3f})"


def write_scene(kind, info):
    ext, nodes = [], []
    ext.append('[ext_resource type="Script" path="res://src/tycoon/campus_building.gd" id="1_bld"]')

    ids = {}

    def glb(path):
        if path not in ids:
            ids[path] = f"m{len(ext)}"
            ext.append(f'[ext_resource type="PackedScene" path="{path}" id="{ids[path]}"]')
        return ids[path]

    for era in range(1, 6):
        nodes.append(f'[node name="Era{era}" type="Node3D" parent="."]' + ("" if era == 1 else "\nvisible = false"))
        for lv in (1, 2, 3):
            lp = f"Era{era}/Level{lv}"
            nodes.append(f'[node name="Level{lv}" type="Node3D" parent="Era{era}"]' + ("" if lv == 1 else "\nvisible = false"))
            rid = glb(f"{RES}/{kind}/{kind}_e{era}_l{lv}.glb")
            nodes.append(f'[node name="Model" parent="{lp}" instance=ExtResource("{rid}")]\n'
                         f"transform = {tf(0, MODEL_Y, 0)}")
            if kind == "pad" and lv == 1:
                rr = glb(f"{RES}/pad/rocket_e{era}.glb")
                nodes.append(f'[node name="Rocket" type="Node3D" parent="{lp}"]\ntransform = {tf(0, 1.2 + MODEL_Y, 0)}')
                nodes.append(f'[node name="Model" parent="{lp}/Rocket" instance=ExtResource("{rr}")]')
            props = info.get("props", {}).get((era, lv), [])
            used = {}
            for (key, x, y, z, turn, name) in props:
                pr = glb(f"{RES}/props/{key}.glb")
                used[name] = used.get(name, 0) + 1
                nm = name if used[name] == 1 else f"{name}{used[name]}"
                nodes.append(f'[node name="{nm}" parent="{lp}" instance=ExtResource("{pr}")]\n'
                             f"transform = {tf(x, y + MODEL_Y, z, turn * math.pi / 2)}")
            lights = info["lights"].get((era, lv), [])
            if lights:
                nodes.append(f'[node name="Lights" type="Node3D" parent="{lp}"]')
            for i, (x, y, z, col, e, rng, sh) in enumerate(lights):
                nodes.append(f'[node name="Light{i + 1}" type="OmniLight3D" parent="{lp}/Lights"]\n'
                             f"transform = {tf(x, y, z)}\nlight_color = {hexc(col)}\nlight_energy = {e:.2f}\n"
                             f"light_specular = 0.3\nomni_range = {rng:.1f}\nomni_attenuation = 1.2"
                             + ("\nshadow_enabled = true" if sh else ""))
    rid = glb(f"{RES}/{kind}/{kind}_scaffold.glb")
    nodes.append('[node name="Scaffold" type="Node3D" parent="."]\nvisible = false')
    nodes.append(f'[node name="Model" parent="Scaffold" instance=ExtResource("{rid}")]\ntransform = {tf(0, MODEL_Y, 0)}')
    nodes.append('[node name="Spots" type="Node3D" parent="."]')
    for (name, (sx, sz), action, yaw, lv, doorway) in SPOTS[kind]:
        mx, mz = door_marker((sx, sz), doorway)
        line = (f'[node name="{name}" type="Marker3D" parent="Spots"]\ntransform = {tf(sx, 0, sz, yaw)}\n'
                f'metadata/action = "{action}"\nmetadata/door = Vector3({mx}, 0, {mz})\nmetadata/level = {lv}')
        via = via_point(doorway)
        if via:
            line += f"\nmetadata/via = Vector3({via[0]}, 0, {via[1]})"
        nodes.append(line)
    root = (f'[node name="{kind.capitalize()}" type="Node3D"]\nscript = ExtResource("1_bld")\nkind = "{kind}"')
    text = (f"[gd_scene load_steps={len(ext) + 1} format=3]\n\n" + "\n".join(ext) + "\n\n" + root + "\n\n"
            + "\n\n".join(nodes) + "\n")
    OUT_BUILD.mkdir(parents=True, exist_ok=True)
    (OUT_BUILD / f"{kind}.tscn").write_text(text, encoding="utf-8", newline="\n")


def main(kinds=None):
    kinds = kinds or list(RECIPES)
    for kind in kinds:
        t0 = time.time()
        info = build_kind(kind)
        write_scene(kind, info)
        print(f"wrote buildings/{kind}.tscn + assets/campus/{kind}/ ({info['tris'] // 1000}k tris, "
              f"{time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main(sys.argv[1:] or None)
