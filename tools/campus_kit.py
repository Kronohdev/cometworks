"""Building kit for the Cometworks campus (used by tools/build_campus_buildings.py).

  STYLES[era]        the five era looks (GDD section 4 / 11): materials as palette indices
  Shell              rooms: plinth, floor, walls with era patterns, windows, doors, roofs,
                     split into the cutaway pieces of tools/campus_voxel.py
  props              furniture and yard props as Stamps (front = +z), cached per era

Era looks: 1 Pioneer (wood planks, corrugated sheet, stepped gable roofs, warm bulbs),
2 Industrial (brick and concrete, flat roofs with parapets), 3 Space race (white panels,
orange stripes, rooftop solar), 4 High-tech (dark metal, teal LED edges, glass),
5 Launch base (silver, voxel domes, violet light, greenhouses).
All sizes in metres; voxels are 10 cm. A Cometling on the campus is ~1.7 m tall.
"""
import math
from functools import lru_cache

import numpy as np

import campus_voxel as cv
from campus_voxel import PAL as P, Stamp, BASE, ROOF, CUT_PX, CUT_NX, CUT_PZ, CUT_NZ, UPPER

T = 0.3          # wall thickness
STUB = 1.0       # wall height that stays when the walls drop (cutaway)
SIDE_TAG = {"px": CUT_PX, "nx": CUT_NX, "pz": CUT_PZ, "nz": CUT_NZ}


def h01(*v):
    """deterministic hash of integers/arrays -> [0, 1)"""
    with np.errstate(over="ignore"):
        acc = np.zeros(1, np.int64)
        for k, a in enumerate(v):
            acc = acc + np.asarray(a, np.int64) * np.int64((73856093, 19349663, 83492791, 265443576)[k % 4])
        acc = (acc ^ (acc >> 13)) * np.int64(1274126177)
        acc = acc ^ (acc >> 16)
    out = (acc & 0xFFFF) / 65536.0
    return out if out.size > 1 or np.ndim(v[0]) else float(out[0])


# ------------------------------------------------------------------ common colours
C = {
    "white": P("#eef1f5"), "paper": P("#f4efe2"), "ink": P("#1b2433"), "dark": P("#141b29"),
    "grey": P("#8f99a8"), "grey_dk": P("#5a6372"), "grey_lt": P("#c3c9d4"), "black": P("#10141c"),
    "orange": P("#ff8a3d"), "orange_dk": P("#d9692a"), "yellow": P("#ffc547"), "red": P("#e2544f"),
    "blue": P("#3f6f9a"), "blue_lt": P("#6aa9ff"), "teal": P("#3fbfa8"), "violet": P("#8e7cff"),
    "leaf": P("#4f9a5e"), "leaf2": P("#3c7d4c"), "leaf3": P("#6cb86a"), "leaf_dk": P("#2f5a40"),
    "pot": P("#b5654a"), "pot2": P("#8a4c3a"), "soil": P("#4a3528"),
    "crate": P("#a07850"), "crate2": P("#8a6440"), "crate_dk": P("#5e4430"),
    "barrel": P("#3f6f9a"), "barrel2": P("#c24a3a"), "rubber": P("#232831"),
    "rocket": P("#eef1f5"), "rocket2": P("#d4d9e1"), "nozzle": P("#3a3f4a"),
    "flower_r": P("#ff6b6b"), "flower_y": P("#ffd166"), "flower_p": P("#f47fa4"),
    "coffee": P("#5a3a28"), "brick_pile": P("#a8644e"), "sand": P("#c9b07a"), "gravel": P("#8a8f96"),
    "hazard": P("#f2b705"), "concrete": P("#9aa1ab"), "concrete_dk": P("#7d8696"), "asphalt": P("#3a4150"),
    "cone": P("#ff7a2e"), "green_glow": P("#7ee08a", 2.0), "red_glow": P("#ff5c6c", 3.0),
    "amber_glow": P("#ffc547", 2.5), "teal_glow": P("#3fe0c5", 2.5), "ice_glow": P("#bfe8ff", 2.2),
    "violet_glow": P("#a08cff", 2.6), "warm_glow": P("#ffd29a", 4.0), "white_glow": P("#f2f6ff", 2.4),
    "orange_glow": P("#ff9a4d", 2.8), "pink_glow": P("#ff8fb8", 2.2),
    "screen_map": P("#1f4a6b", 1.2), "screen_land": P("#3fbf8a", 1.6), "screen_bg": P("#123047", 1.0),
    "fabric_r": P("#c2453f"), "fabric_b": P("#3e5f9e"), "fabric_g": P("#4f8a5e"), "fabric_y": P("#e0a83a"),
    "skin_mat": P("#3d4a63"), "mat_blue": P("#3d6fa8"), "mat_red": P("#c24a4a"),
}


def make_styles():
    S = {}
    S[1] = dict(
        inner=P("#e6d3b0"), skirt=P("#8a6440"), inner_shed=P("#a88a66"),
        era=1, roof_kind="gable", window="cross", wall_kind="planks", shed_kind="corrugated",
        wall=[P("#b0835a"), P("#a2774f"), P("#bb8f63")], wall_dk=P("#7a5236"),
        shed=[P("#9aa3b0"), P("#848e9c")], shed_dk=P("#6c7584"),
        found=P("#8c8273"), found2=P("#766d60"),
        trim=P("#5f4029"), frame=P("#4e3422"), shutter=P("#4f7f9a"),
        roof=[P("#9a4f3a"), P("#87432f")], roof_cap=P("#62301f"), roof_flat=P("#6b3f33"),
        floor=[P("#c69a6c"), P("#b88c60")], floor_seam=P("#9c7350"),
        glass=P("#ffc27a", 2.4), glass_dim=P("#ffb46b", 1.6),
        accent=P("#ff8a3d"), accent2=P("#e9dcc4"),
        desk=P("#8f6440"), desk_top=P("#c49a6c"), chair=P("#7a4f33"), chair2=P("#a04a3a"),
        metal=P("#8f99a8"), metal_dk=P("#5a6372"), cab=P("#9c8a6e"),
        screen=P("#ffb46b", 2.4), screen2=P("#9be08a", 2.0), monitor="crt", case=P("#d8cfb8"),
        lamp=P("#ffd29a", 5.0), led=None, sofa=P("#a8553f"), rug=[P("#9e4a3a"), P("#c9a36a")],
        light="#ffb46b", light_e=1.6, door=P("#6e4a30"), sign=P("#e9dcc4"), banner=P("#c2453f"),
    )
    S[2] = dict(
        inner=P("#ddd6c4"), skirt=P("#6d7a8c"), inner_shed=P("#a9b0ba"),
        era=2, roof_kind="parapet", window="grid", wall_kind="brick", shed_kind="block",
        wall=[P("#a5584a"), P("#93503f"), P("#b4634f")], wall_dk=P("#7a4033"),
        shed=[P("#a9b0ba"), P("#9aa1ac")], shed_dk=P("#7d8696"),
        found=P("#8d949e"), found2=P("#7a828d"),
        trim=P("#b9bec6"), frame=P("#3b4659"), shutter=P("#3b4659"),
        roof=[P("#4a5263"), P("#434b5b")], roof_cap=P("#c3c8cf"), roof_flat=P("#4a5263"),
        floor=[P("#8e959f"), P("#99a0a9")], floor_seam=P("#7a818b"),
        glass=P("#ffcf8a", 2.0), glass_dim=P("#ffc27a", 1.4),
        accent=P("#e9eef7"), accent2=P("#ff8a3d"),
        desk=P("#5f6b7d"), desk_top=P("#b08960"), chair=P("#3e5f7e"), chair2=P("#2e4d6b"),
        metal=P("#8f99a8"), metal_dk=P("#4f5868"), cab=P("#6d7a8c"),
        screen=P("#9be08a", 2.2), screen2=P("#ffc547", 2.0), monitor="crt", case=P("#c9c3b0"),
        lamp=P("#ffe2bf", 4.5), led=None, sofa=P("#3e5f7e"), rug=[P("#3b4f6b"), P("#8a6a4a")],
        light="#ffcf9a", light_e=1.5, door=P("#3b4659"), sign=P("#e9eef7"), banner=P("#2e4d8b"),
    )
    S[3] = dict(
        inner=P("#f1f3f6"), skirt=P("#ff8a3d"), inner_shed=P("#dfe3e9"),
        era=3, roof_kind="flat", window="ribbon", wall_kind="panels", shed_kind="panels",
        wall=[P("#e3e7ee"), P("#d9dee6")], wall_dk=P("#b9c1cc"),
        shed=[P("#d9dee6"), P("#cfd5de")], shed_dk=P("#aab3c0"),
        found=P("#8d949e"), found2=P("#7a828d"),
        trim=P("#ff8a3d"), frame=P("#f4f6f9"), shutter=P("#ff8a3d"),
        roof=[P("#59647a"), P("#525c71")], roof_cap=P("#e3e7ee"), roof_flat=P("#59647a"),
        floor=[P("#d6dbe3"), P("#c3cad4")], floor_seam=P("#aab2be"),
        glass=P("#cdeeff", 1.7), glass_dim=P("#bfe8ff", 1.2),
        accent=P("#ff8a3d"), accent2=P("#3f6f9a"),
        desk=P("#d9dee6"), desk_top=P("#eef1f5"), chair=P("#ff8a3d"), chair2=P("#3f6f9a"),
        metal=P("#a3adb8"), metal_dk=P("#6d7787"), cab=P("#cfd5de"),
        screen=P("#bfe8ff", 2.2), screen2=P("#ffb46b", 2.0), monitor="flat", case=P("#e3e7ee"),
        lamp=P("#f2f6ff", 4.0), led=None, sofa=P("#ff8a3d"), rug=[P("#3f6f9a"), P("#e3e7ee")],
        light="#eaf2ff", light_e=1.5, door=P("#59647a"), sign=P("#ff8a3d"), banner=P("#ff8a3d"),
    )
    S[4] = dict(
        inner=P("#3a4458"), skirt=P("#3fe0c5", 1.6), inner_shed=P("#2f3a4e"),
        era=4, roof_kind="flat", window="curtain", wall_kind="metal", shed_kind="metal",
        wall=[P("#2f3a4e"), P("#2a3446")], wall_dk=P("#1f2838"),
        shed=[P("#36425a"), P("#303b51")], shed_dk=P("#232c3d"),
        found=P("#232a37"), found2=P("#1b212c"),
        trim=P("#3fe0c5", 2.6), frame=P("#1b2230"), shutter=P("#1b2230"),
        roof=[P("#1f2838"), P("#1b2433")], roof_cap=P("#3a465c"), roof_flat=P("#1f2838"),
        floor=[P("#323c50"), P("#2c3547")], floor_seam=P("#3fe0c5", 0.6),
        glass=P("#8fd8ff", 1.5), glass_dim=P("#7cc6f0", 1.0),
        accent=P("#3fe0c5"), accent2=P("#e9eef7"),
        desk=P("#202838"), desk_top=P("#e9eef7"), chair=P("#2b3548"), chair2=P("#3fbfa8"),
        metal=P("#7d8799"), metal_dk=P("#3a4458"), cab=P("#2b3548"),
        screen=P("#3fe0c5", 2.4), screen2=P("#8fd8ff", 2.2), monitor="flat", case=P("#1b2230"),
        lamp=P("#d6fff6", 4.0), led=P("#3fe0c5", 3.0), sofa=P("#2f8f80"), rug=[P("#1f6b62"), P("#2b3548")],
        light="#cfefff", light_e=1.6, door=P("#141b29"), sign=P("#3fe0c5", 2.4), banner=P("#2f8f80"),
    )
    S[5] = dict(
        inner=P("#e7e9f3"), skirt=P("#8e7cff", 1.6), inner_shed=P("#cfd5de"),
        era=5, roof_kind="dome", window="porthole", wall_kind="silver", shed_kind="silver",
        wall=[P("#c9cfda"), P("#bfc6d2")], wall_dk=P("#959dae"),
        shed=[P("#c3c9d4"), P("#b7bec9")], shed_dk=P("#8f99ad"),
        found=P("#6b7487"), found2=P("#5a6378"),
        trim=P("#8e7cff", 2.6), frame=P("#e6eaf1"), shutter=P("#8e7cff"),
        roof=[P("#8f99ad"), P("#858fa3")], roof_cap=P("#dfe4ee"), roof_flat=P("#8f99ad"),
        floor=[P("#d2d7e2"), P("#c6ccd8")], floor_seam=P("#a08cff", 0.8),
        glass=P("#c9bcff", 1.7), glass_dim=P("#b6a8ff", 1.2),
        accent=P("#8e7cff"), accent2=P("#e9eef7"),
        desk=P("#dfe4ee"), desk_top=P("#f4f6fa"), chair=P("#8e7cff"), chair2=P("#6f5fd6"),
        metal=P("#b7bec9"), metal_dk=P("#7a8396"), cab=P("#cfd5de"),
        screen=P("#b6a8ff", 2.6), screen2=P("#7ee0ff", 2.4), monitor="holo", case=P("#dfe4ee"),
        lamp=P("#efeaff", 4.0), led=P("#a08cff", 3.0), sofa=P("#6f5fd6"), rug=[P("#4b3f9e"), P("#c9cfda")],
        light="#ece6ff", light_e=1.6, door=P("#5a6378"), sign=P("#a08cff", 2.4), banner=P("#6f5fd6"),
    )
    return S


STYLES = make_styles()

STAR = ["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."]
ROCKET_ICON = ["..#..", ".###.", ".#o#.", ".###.", ".###.", "##.##", "#f.f#", "..f.."]


# ------------------------------------------------------------------ wall patterns
def wall_pattern(st, X, Y, Z, side, y0, h, shed=False):
    """palette index per wall voxel (arrays broadcast to the region)"""
    along = X if side in ("pz", "nz") else Z
    a10 = np.floor(along * 10 + 1e-6).astype(np.int64)
    y10 = np.floor((Y - y0) * 10 + 1e-6).astype(np.int64)
    kind = st["shed_kind"] if shed else st["wall_kind"]
    tones = st["shed"] if shed else st["wall"]
    shape = np.broadcast_shapes(np.shape(along), np.shape(Y))
    out = np.empty(shape, np.int64)
    a10 = np.broadcast_to(a10, shape)
    y10 = np.broadcast_to(y10, shape)
    if kind == "planks":
        plank = np.floor_divide(a10, 3)
        t = (h01(plank, 7) * 3).astype(int)
        out[:] = np.choose(t, tones)
        out[(y10 % 12) == 0] = st["wall_dk"]                       # battens
    elif kind == "corrugated":
        out[:] = np.where(np.floor_divide(a10, 2) % 2 == 0, tones[0], tones[1])
        out[(y10 % 24) == 23] = st["shed_dk"]
    elif kind == "brick":
        row = y10
        brick = np.floor_divide(a10 + (row % 2) * 2, 4)
        hb = h01(brick, row, 3)
        t = np.where(hb < 0.72, 0, np.where(hb < 0.86, 1, 2))
        out[:] = np.choose(t, tones)
        out[y10 < 3] = st["trim"]                                    # concrete footing band
    elif kind == "block":
        row = np.floor_divide(y10, 2)
        blk = np.floor_divide(a10 + (row % 2) * 2, 4)
        t = (h01(blk, row, 5) < 0.2).astype(int)
        out[:] = np.choose(t, tones)
        out[(y10 % 4 == 3)] = st["shed_dk"]
    elif kind == "panels":
        out[:] = tones[0]
        out[(a10 % 12 == 0) | (y10 % 12 == 0)] = st["wall_dk"]
        band = (y10 >= int(h * 10) - 9) & (y10 < int(h * 10) - 6)
        out[band] = st["trim"]
    elif kind == "metal":
        out[:] = np.where(np.floor_divide(a10, 6) % 2 == 0, tones[0], tones[1])
        out[(a10 % 12 == 0)] = st["wall_dk"]
        out[(y10 % 16 == 0)] = st["wall_dk"]
    else:  # silver
        out[:] = tones[0]
        out[(y10 % 8 == 0)] = tones[1]
        out[(a10 % 16 == 0)] = st["wall_dk"]
        out[(y10 >= 6) & (y10 < 7)] = st["trim"]
    return out


# ------------------------------------------------------------------ shell
class Wall:
    """Feature helper on one wall face. Coordinates: a = along the wall (world x for
    pz/nz, world z for px/nx), y = height, d = outward distance from the outer face."""

    def __init__(self, g, side, face, ybase, upper):
        self.g, self.side, self.face, self.ybase, self.upper = g, side, face, ybase, upper

    def tag_for(self, y):
        if self.upper:
            return UPPER
        return BASE if y < self.ybase + STUB - 1e-6 else SIDE_TAG[self.side]

    def _world(self, a0, a1, d0, d1):
        f, s = self.face, self.side
        if s == "pz":
            return a0, a1, f + d0, f + d1
        if s == "nz":
            return a0, a1, f - d1, f - d0
        if s == "px":
            return f + d0, f + d1, a0, a1
        return f - d1, f - d0, a0, a1

    def box(self, a0, a1, y0, y1, d0, d1, c, tag=None):
        x0, x1, z0, z1 = self._world(a0, a1, d0, d1)
        if tag is not None:
            self.g.box(x0, x1, y0, y1, z0, z1, c, tag)
            return
        cut = self.ybase + STUB
        if y0 < cut < y1 and not self.upper:
            self.g.box(x0, x1, y0, cut, z0, z1, c, BASE)
            self.g.box(x0, x1, cut, y1, z0, z1, c, SIDE_TAG[self.side])
        else:
            self.g.box(x0, x1, y0, y1, z0, z1, c, self.tag_for(y0))

    def clear(self, a0, a1, y0, y1, d0, d1):
        x0, x1, z0, z1 = self._world(a0, a1, d0, d1)
        self.g.clear(x0, x1, y0, y1, z0, z1)

    def disc(self, ac, yc, r, d0, d1, c, rin=None, clear=False):
        x0, x1, z0, z1 = self._world(ac - r - 0.1, ac + r + 0.1, d0, d1)
        s, X, Y, Z = self.g.region(x0, x1, yc - r - 0.1, yc + r + 0.1, z0, z1)
        A = X if self.side in ("pz", "nz") else Z
        R = np.sqrt((A - ac) ** 2 + (Y - yc) ** 2)
        m = R <= r
        if rin is not None:
            m = m & (R > rin)
        m = np.broadcast_to(m, self.g.col[s].shape)
        if clear:
            self.g.put_mask(s, m, 0)
        else:
            self.g.put_mask(s, m, c, tag=self.tag_for(yc))


class Room:
    """A rectangular room: outer footprint x0..x1, z0..z1, floor at y0, walls h tall."""

    def __init__(self, x0, x1, z0, z1, h, y0=0.0, upper=False, shed=False):
        self.x0, self.x1, self.z0, self.z1, self.h, self.y0 = x0, x1, z0, z1, h, y0
        self.upper, self.shed = upper, shed
        self.doors = []          # (side, a_centre, width, height)

    @property
    def top(self):
        return self.y0 + self.h

    def inner(self):
        return self.x0 + T, self.x1 - T, self.z0 + T, self.z1 - T


def build_room(g, st, r, doors=(), windows=True, win_skip=(), roof=True, roof_kind=None, floor=True,
               win_h=None, gable_axis="x", door_style=None, awning=True, lamps=True, dressing=True,
               reserved=()):
    """Walls, floor, windows, doors and roof of a room. doors: [(side, a, w, h)] with a =
    centre along the wall."""
    tag_all = UPPER if r.upper else None
    base_tag = UPPER if r.upper else BASE
    x0, x1, z0, z1, y0, h = r.x0, r.x1, r.z0, r.z1, r.y0, r.h
    r.doors = list(doors)
    # plinth and floor
    if y0 == 0.0:
        g.box(x0 - 0.1, x1 + 0.1, 0, 0.1, z0 - 0.1, z1 + 0.1, st["found2"], base_tag)
    if floor:
        fy0 = y0 if y0 > 0 else 0.0
        s, X, Y, Z = g.region(x0 + T, x1 - T, fy0, fy0 + 0.1, z0 + T, z1 - T)
        fx = np.floor(X * 10 + 1e-6).astype(np.int64)
        fz = np.floor(Z * 10 + 1e-6).astype(np.int64)
        if st["era"] == 1:      # boards along x
            board = np.floor_divide(fz, 2)
            fl = np.where(h01(board, np.floor_divide(fx + board * 7, 12)) < 0.5, st["floor"][0], st["floor"][1])
            fl = np.where((fx + board * 7) % 12 == 0, st["floor_seam"], fl)
        elif st["era"] in (2, 3):  # tiles 0.5 m checker
            fl = np.where((np.floor_divide(fx, 5) + np.floor_divide(fz, 5)) % 2 == 0, st["floor"][0], st["floor"][1])
        else:
            fl = np.where((np.floor_divide(fx, 6) + np.floor_divide(fz, 6)) % 2 == 0, st["floor"][0], st["floor"][1])
            fl = np.where(((fx % 24) == 0) | ((fz % 24) == 0), st["floor_seam"], fl)
        fl = np.broadcast_to(fl, g.col[s].shape)
        sub_c, sub_t = g.col[s], g.tag[s]
        sub_c[...] = fl
        sub_t[...] = base_tag
    fy = y0 + 0.1                          # walking surface inside
    wy0 = y0
    # walls: front/back span the full width (they own the corners)
    sides = {
        "pz": (x0, x1, z1 - T, z1, z1), "nz": (x0, x1, z0, z0 + T, z0),
        "px": (z0 + T, z1 - T, x1 - T, x1, x1), "nx": (z0 + T, z1 - T, x0, x0 + T, x0),
    }
    walls = {}
    for side, (a0, a1, b0, b1, face) in sides.items():
        if side in ("pz", "nz"):
            s, X, Y, Z = g.region(a0, a1, wy0, wy0 + h, b0, b1)
        else:
            s, X, Y, Z = g.region(b0, b1, wy0, wy0 + h, a0, a1)
        pat = wall_pattern(st, X, Y, Z, side, wy0, h, r.shed)
        pat = np.broadcast_to(pat, g.col[s].shape)
        Yb = np.broadcast_to(Y, g.col[s].shape)
        tags = np.where(Yb < wy0 + STUB, BASE, SIDE_TAG[side]) if not r.upper else np.full(Yb.shape, UPPER)
        g.col[s] = pat
        g.tag[s] = tags
        walls[side] = Wall(g, side, face, wy0, r.upper)
    # interior faces: plain paint with a skirting
    inner = st["inner_shed"] if r.shed else st["inner"]
    for (ax0, ax1, az0, az1) in ((x0 + T - 0.1, x0 + T, z0, z1), (x1 - T, x1 - T + 0.1, z0, z1),
                                 (x0, x1, z0 + T - 0.1, z0 + T), (x0, x1, z1 - T, z1 - T + 0.1)):
        g.paint(ax0, ax1, wy0 + 0.3, wy0 + h, az0, az1, inner)
        g.paint(ax0, ax1, wy0 + 0.1, wy0 + 0.3, az0, az1, st["skirt"])
    # soften the outer corners (one voxel chamfer) and add corner posts
    for (cx, cz) in ((x0, z0), (x1, z0), (x0, z1), (x1, z1)):
        ax = (cx, cx + 0.1) if cx == x0 else (cx - 0.1, cx)
        az = (cz, cz + 0.1) if cz == z0 else (cz - 0.1, cz)
        g.clear(ax[0], ax[1], wy0 + 0.1, wy0 + h, az[0], az[1])
    corner_posts(g, st, r, walls)
    # corrugated sheds get ridges
    if r.shed and st["shed_kind"] == "corrugated":
        for side, wl in walls.items():
            a0, a1 = (x0, x1) if side in ("pz", "nz") else (z0, z1)
            a = a0 + 0.3
            while a < a1 - 0.3:
                wl.box(a, a + 0.1, wy0 + 0.3, wy0 + h - 0.1, 0, 0.1, st["shed"][1])
                a += 0.8
    # doors
    for (side, a, w, dh) in doors:
        door(g, st, walls[side], a, w, dh, wy0, fy, style=door_style, awning=awning, lamps=lamps, top=wy0 + h)
    # windows
    if windows:
        for side, wl in walls.items():
            if side in win_skip:
                continue
            a0, a1 = (x0, x1) if side in ("pz", "nz") else (z0, z1)
            k = 0
            while k == 0 or wy0 + k * 3.2 + STUB + 0.2 + 1.3 <= wy0 + h - 0.6:
                yb = wy0 + k * 3.2
                blocked = [(a - w / 2 - 0.5, a + w / 2 + 0.5) for (sd, a, w, dh) in doors
                           if sd == side and wy0 + dh + 1.4 > yb + STUB]
                window_row(g, st, wl, a0 + 0.7, a1 - 0.7, yb, h if k == 0 else 3.4, blocked, win_h)
                k += 1
    wall_trim(g, st, r, walls)
    if roof:
        kind = roof_kind or st["roof_kind"]
        make_roof(g, st, r, kind, gable_axis)
        if dressing and kind not in ("gable", "sawtooth"):
            roof_dressing(g, st, r, reserved)
    return walls


def wall_trim(g, st, r, walls):
    """era bands near the wall top (cornice, LED line, ribs)"""
    era = st["era"]
    x0, x1, z0, z1, y0, h = r.x0, r.x1, r.z0, r.z1, r.y0, r.h
    top = y0 + h
    for side, wl in walls.items():
        a0, a1 = (x0 + 0.1, x1 - 0.1) if side in ("pz", "nz") else (z0 + 0.1, z1 - 0.1)
        # doorways on this wall (with their frames): the plinth bands stop at them, so no
        # kerb runs across a door, and ribs start above the door
        gaps = sorted((a - w / 2 - 0.2, a + w / 2 + 0.2, y0 + dh + 0.3)
                      for (sd, a, w, dh) in getattr(r, "doors", []) if sd == side)

        def plinth(ya, yb, col):
            lo = a0
            for (g0, g1, _t) in gaps:
                if g0 > lo:
                    wl.box(lo, min(g0, a1), ya, yb, 0.0, 0.1, col)
                lo = max(lo, g1)
            if lo < a1:
                wl.box(lo, a1, ya, yb, 0.0, 0.1, col)

        if era == 2:
            wl.box(a0, a1, top - 0.4, top - 0.2, 0.0, 0.1, st["trim"])
            for a in np.arange(a0 + 0.2, a1 - 0.1, 0.4):
                wl.box(a, a + 0.1, top - 0.5, top - 0.4, 0.0, 0.1, st["trim"])
        elif era == 3:
            plinth(y0 + 0.1, y0 + 0.3, st["wall_dk"])
        elif era == 4:
            wl.box(a0, a1, top - 0.3, top - 0.2, 0.0, 0.1, st["led"])
            plinth(y0 + 0.1, y0 + 0.2, st["led"])
        elif era == 5:
            wl.box(a0, a1, top - 0.5, top - 0.4, 0.0, 0.1, st["trim"])
            plinth(y0 + 0.1, y0 + 0.4, st["wall_dk"])
            for a in np.arange(a0 + 0.7, a1 - 0.5, 1.6):
                yb = y0 + 0.4
                for (g0, g1, t) in gaps:
                    if a + 0.2 > g0 and a < g1:
                        yb = max(yb, t)
                if yb < top - 0.5:
                    wl.box(a, a + 0.2, yb, top - 0.5, 0.0, 0.1, st["wall"][1])


def roof_dressing(g, st, r, reserved=()):
    """rooftop kit on flat roofs: AC units, vents, skylights, solar rows, domes, greenhouses"""
    era = st["era"]
    tag = UPPER if r.upper else ROOF
    y = roof_top(r, era)
    ax0, ax1, az0, az1 = r.x0 + 0.7, r.x1 - 0.7, r.z0 + 0.7, r.z1 - 0.7
    sw, sd = 2.6, 2.2
    nx, nz = int((ax1 - ax0) // sw), int((az1 - az0) // sd)
    if nx <= 0 or nz <= 0:
        return
    ox = ax0 + ((ax1 - ax0) - nx * sw) / 2
    oz = az0 + ((az1 - az0) - nz * sd) / 2
    used = set()
    seed = int(abs(r.x0 * 7 + r.z0 * 13 + r.x1 * 3)) + era * 101
    big = nx * nz >= 6
    for i in range(nx):
        for j in range(nz):
            if (i, j) in used:
                continue
            cx, cz = ox + (i + 0.5) * sw, oz + (j + 0.5) * sd
            if any(rx0 - 1.2 < cx < rx1 + 1.2 and rz0 - 1.0 < cz < rz1 + 1.0 for (rx0, rx1, rz0, rz1) in reserved):
                continue
            hsh = float(h01(seed, i, j))
            cxr, czr = round(cx * 10) / 10, round(cz * 10) / 10
            if era == 2:
                if big and (i, j) == (nx - 1, 0):
                    g.stamp(water_tank(era), cxr, czr, 0, y, tag)
                elif hsh < 0.3:
                    g.stamp(ac_unit(era), cxr, czr, (i + j) % 4, y, tag)
                elif hsh < 0.5:
                    g.stamp(vent(era), cxr - 0.5, czr, 0, y, tag)
                    g.stamp(vent(era), cxr + 0.5, czr, 0, y, tag)
                elif hsh < 0.72:
                    g.stamp(skylight(era, 2.0, 1.2), cxr, czr, 0, y, tag)
                elif hsh < 0.8:
                    g.stamp(hatch(era), cxr, czr, 0, y, tag)
            elif era == 3:
                if hsh < 0.62:
                    g.stamp(solar_panel(era, 2.2, 1.2), cxr, czr, 0, y, tag)
                elif hsh < 0.76:
                    g.stamp(vent(era), cxr, czr, 0, y, tag)
                elif hsh < 0.88:
                    g.stamp(ac_unit(era), cxr, czr, 1, y, tag)
                else:
                    g.stamp(hatch(era), cxr, czr, 0, y, tag)
            elif era == 4:
                if hsh < 0.3:
                    g.stamp(ac_unit(era), cxr, czr, (i + j) % 4, y, tag)
                elif hsh < 0.58:
                    g.stamp(skylight(era, 2.2, 1.4), cxr, czr, 0, y, tag)
                elif hsh < 0.82:
                    g.stamp(solar_panel(era, 2.2, 1.2), cxr, czr, 0, y, tag)
                else:
                    g.stamp(vent(era), cxr, czr, 0, y, tag)
            else:
                if big and (i + 1 < nx) and (i, j + 1) not in used and hsh < 0.22 and ("gh" not in used):
                    g.stamp(greenhouse(era, 4.6, 1.8, 1.6), round((cx + sw / 2) * 10) / 10, czr, 0, y, tag)
                    used |= {(i + 1, j), "gh"}
                elif hsh < 0.34:
                    g.stamp(dome(era, 0.9), cxr, czr, 0, y, tag)
                elif hsh < 0.7:
                    g.stamp(solar_panel(era, 2.2, 1.2), cxr, czr, 0, y, tag)
                elif hsh < 0.85:
                    g.stamp(vent(era), cxr, czr, 0, y, tag)
    # corner beacons on the launch-base roofs
    if era == 5:
        for (bx, bz) in ((r.x0 + 0.2, r.z0 + 0.2), (r.x1 - 0.4, r.z1 - 0.4)):
            g.box(bx, bx + 0.2, y, y + 0.6, bz, bz + 0.2, st["metal_dk"], tag)
            g.box(bx, bx + 0.2, y + 0.6, y + 0.8, bz, bz + 0.2, C["violet_glow"], tag)


def corner_posts(g, st, r, walls):
    era = st["era"]
    x0, x1, z0, z1, y0, h = r.x0, r.x1, r.z0, r.z1, r.y0, r.h
    for (cx, cz, sx, sz) in ((x0, z0, -1, -1), (x1, z0, 1, -1), (x0, z1, -1, 1), (x1, z1, 1, 1)):
        side = "pz" if sz > 0 else "nz"
        wl = walls[side]
        col = {1: st["trim"], 2: st["trim"], 3: st["wall_dk"], 4: st["led"], 5: st["wall"][1]}[era]
        # a post standing 0.1 proud of both faces, 0.2 wide, set back from the chamfer
        px0 = cx - 0.1 if sx < 0 else cx - 0.2
        pz0 = cz - 0.1 if sz < 0 else cz - 0.2
        if era == 4:
            # LED edge: glowing line just off the corner
            for (ya, yb) in ((y0 + 0.1, y0 + STUB), (y0 + STUB, y0 + h)):
                tag = UPPER if r.upper else (BASE if ya < y0 + STUB else SIDE_TAG[side])
                g.box(cx if sx < 0 else cx - 0.1, cx + 0.1 if sx < 0 else cx, ya, yb,
                      cz if sz < 0 else cz - 0.1, cz + 0.1 if sz < 0 else cz, col, tag)
            continue
        if era == 2:   # concrete quoins every other row
            for k in range(int(h / 0.4)):
                yy = y0 + 0.2 + k * 0.4
                if yy + 0.2 > y0 + h:
                    break
                w = 0.3 if k % 2 == 0 else 0.2
                xa = cx - 0.1 if sx < 0 else cx - w + 0.1
                za = cz - 0.1 if sz < 0 else cz - w + 0.1
                tag = UPPER if r.upper else (BASE if yy < y0 + STUB else SIDE_TAG[side])
                g.box(xa, xa + w, yy, yy + 0.2, za, za + w, col, tag)
            continue
        zx = (x0, x0 + 0.2) if sx < 0 else (x1 - 0.2, x1)
        zz = (z0 - 0.1, z0) if sz < 0 else (z1, z1 + 0.1)
        xx = (x0 - 0.1, x0) if sx < 0 else (x1, x1 + 0.1)
        xz = (z0, z0 + 0.2) if sz < 0 else (z1 - 0.2, z1)
        for (ya, yb) in ((y0 + 0.1, min(y0 + STUB, y0 + h)), (y0 + STUB, y0 + h)):
            if yb <= ya:
                continue
            tag = UPPER if r.upper else (BASE if ya < y0 + STUB else SIDE_TAG[side])
            g.box(zx[0], zx[1], ya, yb, zz[0], zz[1], col, tag)
            g.box(xx[0], xx[1], ya, yb, xz[0], xz[1], col, tag)


def window_row(g, st, wl, a0, a1, y0, h, blocked, win_h=None):
    kind = st["window"]
    ww = {"cross": 1.0, "grid": 1.4, "ribbon": 2.2, "curtain": 1.6, "porthole": 1.0}[kind]
    gap = {"cross": 1.2, "grid": 1.0, "ribbon": 0.8, "curtain": 0.4, "porthole": 1.2}[kind]
    wh = win_h or min(1.3, h - 2.0)
    if kind == "ribbon":
        wh = min(wh, 0.9)
    if kind == "curtain":
        wh = min(h - 1.6, 2.2) if win_h is None else win_h
    if wh < 0.5:
        return
    sill = y0 + STUB + 0.2 if kind != "curtain" else y0 + STUB + 0.1
    # free segments between blocked ranges
    segs = [(a0, a1)]
    for (b0, b1) in blocked:
        nxt = []
        for (s0, s1) in segs:
            if b1 <= s0 or b0 >= s1:
                nxt.append((s0, s1))
                continue
            if b0 > s0:
                nxt.append((s0, b0))
            if b1 < s1:
                nxt.append((b1, s1))
        segs = nxt
    k = 0
    for (s0, s1) in segs:
        L = s1 - s0
        n = int((L + gap) // (ww + gap))
        if n <= 0:
            continue
        span = n * ww + (n - 1) * gap
        start = s0 + (L - span) / 2
        for i in range(n):
            a = round((start + i * (ww + gap) + ww / 2) * 10) / 10
            window(g, st, wl, a, ww, sill, wh, k)
            k += 1


def window(g, st, wl, a, ww, sill, wh, k):
    kind = st["window"]
    hw = ww / 2
    fr = st["frame"]
    if kind == "porthole":
        r = ww / 2
        yc = sill + r
        wl.disc(a, yc, r, -T, 0.0, 0, clear=True)
        wl.disc(a, yc, r, -0.2, -0.1, st["glass"])
        wl.disc(a, yc, r + 0.15, 0.0, 0.1, fr, rin=r - 0.05)
        wl.box(a - 0.05, a + 0.05, yc - r, yc + r, -0.2, -0.1, st["wall_dk"])
        return
    wl.clear(a - hw, a + hw, sill, sill + wh, -T, 0.0)
    wl.box(a - hw, a + hw, sill, sill + wh, -0.2, -0.1, st["glass"])
    if kind == "cross":
        wl.box(a - hw - 0.1, a + hw + 0.1, sill - 0.1, sill, 0, 0.2, fr)          # sill
        wl.box(a - hw - 0.1, a + hw + 0.1, sill + wh, sill + wh + 0.1, 0, 0.1, fr)  # head
        wl.box(a - hw - 0.1, a - hw, sill, sill + wh, 0, 0.1, fr)
        wl.box(a + hw, a + hw + 0.1, sill, sill + wh, 0, 0.1, fr)
        wl.box(a - 0.05, a + 0.05, sill, sill + wh, -0.2, -0.1, fr)
        my = round((sill + wh / 2) * 10) / 10
        wl.box(a - hw, a + hw, my, my + 0.1, -0.2, -0.1, fr)
        # shutters
        wl.box(a - hw - 0.5, a - hw - 0.1, sill, sill + wh, 0, 0.1, st["shutter"])
        wl.box(a + hw + 0.1, a + hw + 0.5, sill, sill + wh, 0, 0.1, st["shutter"])
        for yy in np.arange(sill + 0.2, sill + wh - 0.1, 0.3):
            wl.box(a - hw - 0.5, a - hw - 0.1, yy, yy + 0.1, 0.1, 0.2, st["trim"])
            wl.box(a + hw + 0.1, a + hw + 0.5, yy, yy + 0.1, 0.1, 0.2, st["trim"])
        if k % 2 == 0:   # flower box
            wl.box(a - hw, a + hw, sill - 0.4, sill - 0.1, 0.1, 0.4, st["trim"])
            for i, x in enumerate(np.arange(a - hw + 0.1, a + hw - 0.05, 0.2)):
                c = (C["flower_r"], C["flower_y"], C["flower_p"])[(i + k) % 3]
                wl.box(x, x + 0.1, sill - 0.1, sill + 0.1, 0.2, 0.3, C["leaf"])
                wl.box(x, x + 0.1, sill + 0.1, sill + 0.2, 0.2, 0.3, c)
    elif kind == "grid":
        wl.box(a - hw - 0.2, a + hw + 0.2, sill - 0.2, sill, 0, 0.2, st["trim"])          # concrete sill
        wl.box(a - hw - 0.2, a + hw + 0.2, sill + wh, sill + wh + 0.3, 0, 0.1, st["trim"])  # lintel
        for x in (a - hw / 3, a + hw / 3):
            xx = round(x * 10) / 10
            wl.box(xx - 0.05, xx + 0.05, sill, sill + wh, -0.2, -0.1, fr)
        my = round((sill + wh * 0.55) * 10) / 10
        wl.box(a - hw, a + hw, my, my + 0.1, -0.2, -0.1, fr)
    elif kind == "ribbon":
        # rounded white frame and an orange stripe running under the window row
        wl.box(a - hw - 0.1, a + hw + 0.1, sill - 0.1, sill + wh + 0.1, 0, 0.1, fr)
        wl.clear(a - hw, a + hw, sill, sill + wh, 0, 0.1)
        for (ca, cy) in ((a - hw - 0.1, sill - 0.1), (a + hw, sill - 0.1), (a - hw - 0.1, sill + wh), (a + hw, sill + wh)):
            wl.clear(ca, ca + 0.1, cy, cy + 0.1, 0, 0.1)
        wl.box(a - hw, a + hw, sill, sill + 0.1, -0.2, -0.1, fr)
        for x in np.arange(a - hw + 0.7, a + hw - 0.3, 0.7):
            xx = round(x * 10) / 10
            wl.box(xx, xx + 0.1, sill, sill + wh, -0.2, -0.1, fr)
    elif kind == "curtain":
        wl.box(a - hw, a + hw, sill - 0.1, sill, 0, 0.1, st["led"])
        for x in np.arange(a - hw, a + hw + 0.01, 0.4):
            xx = round(x * 10) / 10
            wl.box(xx - 0.05, xx + 0.05, sill, sill + wh, -0.1, 0.0, fr)
        wl.box(a - hw, a + hw, sill + wh, sill + wh + 0.1, -0.1, 0.0, fr)


def door(g, st, wl, a, w, dh, y0, fy, style=None, awning=True, lamps=True, top=99.0):
    """Doorway through a wall with frame, open leaf, step, sign board and lamp."""
    era = st["era"]
    hw = w / 2
    wl.clear(a - hw, a + hw, y0 + 0.1, y0 + dh, -T - 0.05, 0.05)
    # the threshold: floor through the gap
    wl.box(a - hw, a + hw, y0, y0 + 0.1, -T, 0.0, st["found"])
    big = w >= 3.0 or dh >= 4.0
    fr = st["frame"] if era != 4 else st["metal_dk"]
    wl.box(a - hw - 0.2, a - hw, y0 + 0.1, y0 + dh + 0.2, 0.0, 0.1, fr)
    wl.box(a + hw, a + hw + 0.2, y0 + 0.1, y0 + dh + 0.2, 0.0, 0.1, fr)
    wl.box(a - hw - 0.2, a + hw + 0.2, y0 + dh, y0 + dh + 0.2, 0.0, 0.1, fr)
    if era == 4:
        wl.box(a - hw - 0.3, a + hw + 0.3, y0 + dh + 0.2, y0 + dh + 0.3, 0.0, 0.1, st["led"])
    if era == 5:
        wl.box(a - hw - 0.2, a + hw + 0.2, y0 + dh + 0.2, y0 + dh + 0.3, 0.0, 0.1, st["trim"])
    if big:
        # roll-up door rolled at the top, with hazard edge
        wl.box(a - hw, a + hw, y0 + dh - 0.5, y0 + dh, -0.2, 0.0, st["metal_dk"])
        wl.box(a - hw, a + hw, y0 + dh - 0.6, y0 + dh - 0.5, -0.2, 0.0, C["hazard"])
        # hazard stripes on the jambs
        for yy in np.arange(y0 + 0.1, y0 + 1.3, 0.2):
            c = C["hazard"] if int(round(yy * 5)) % 2 == 0 else C["ink"]
            wl.box(a - hw - 0.2, a - hw, yy, yy + 0.2, 0.1, 0.2, c)
            wl.box(a + hw, a + hw + 0.2, yy, yy + 0.2, 0.1, 0.2, c)
    else:
        # one open leaf swung inside against the wall
        leaf = st["door"]
        lw = min(w, 1.2)
        wl.box(a + hw, a + hw + lw, y0 + 0.1, y0 + dh - 0.1, -T - 0.1, -T, leaf)
        wl.box(a + hw + 0.1, a + hw + 0.2, y0 + 1.1, y0 + 1.2, -T - 0.2, -T - 0.1, C["yellow"])
    # step / mat outside
    if y0 == 0.0:
        wl.box(a - hw - 0.2, a + hw + 0.2, 0.0, 0.1, 0.0, 0.6, C["concrete"])
        if not big:
            wl.box(a - hw + 0.2, a + hw - 0.2, 0.1, 0.15, 0.1, 0.5, st["rug"][0])
    # awning / canopy
    if awning:
        ay = y0 + dh + 0.3
        dep = 0.9 if not big else 0.7
        if era == 1:
            for i, dd in enumerate(np.arange(0.1, dep + 0.01, 0.2)):
                yy = ay + 0.3 - i * 0.1
                for x in np.arange(a - hw - 0.4, a + hw + 0.4, 0.1):
                    c = st["roof"][int(round(x * 10)) // 4 % 2]
                    wl.box(x, x + 0.1, yy, yy + 0.1, dd - 0.1, dd + 0.1, c)
            for x in (a - hw - 0.3, a + hw + 0.2):
                wl.box(x, x + 0.1, ay - 0.3, ay + 0.2, 0.1, dep - 0.2, st["trim"])
        else:
            col = {2: st["trim"], 3: C["white"], 4: st["roof"][0], 5: st["wall"][0]}[era]
            wl.box(a - hw - 0.4, a + hw + 0.4, ay, ay + 0.2, 0.0, dep, col)
            edge = {2: st["trim"], 3: C["orange"], 4: st["led"], 5: st["trim"]}[era]
            wl.box(a - hw - 0.4, a + hw + 0.4, ay - 0.1, ay, dep - 0.1, dep, edge)
            if era == 3:
                wl.box(a - hw - 0.4, a + hw + 0.4, ay + 0.2, ay + 0.3, 0.0, dep, C["orange"])
    # sign board with the agency star above the awning
    sy = y0 + dh + (0.7 if awning else 0.3)
    if sy + 0.9 <= top - 0.1 and w < 5.0:
        sw = min(w + 0.6, 3.2)
        wl.box(a - sw / 2, a + sw / 2, sy, sy + 0.8, 0.0, 0.1, st["sign"] if era != 4 else st["metal_dk"])
        wl.box(a - sw / 2 - 0.1, a + sw / 2 + 0.1, sy - 0.1, sy, 0.0, 0.2, st["trim"] if era != 4 else st["led"])
        star_on_wall(wl, a, sy + 0.4, 0.1, 0.2, C["orange"] if era != 3 else st["accent2"], scale=0.1)
    # door lamps
    if lamps:
        for x in (a - hw - 0.6, a + hw + 0.4):
            wl.box(x, x + 0.2, y0 + dh - 0.4, y0 + dh - 0.1, 0.0, 0.3, st["metal_dk"])
            wl.box(x, x + 0.2, y0 + dh - 0.6, y0 + dh - 0.4, 0.1, 0.3, st["lamp"])


def star_on_wall(wl, ac, yc, d0, d1, col, scale=0.1):
    n = len(STAR)
    for i, row in enumerate(STAR):
        for j, ch in enumerate(row):
            if ch == "#":
                a = ac + (j - n // 2 - 0.5) * scale
                y = yc + (n // 2 - i - 0.5) * scale
                wl.box(round(a * 10) / 10, round(a * 10) / 10 + scale, round(y * 10) / 10,
                       round(y * 10) / 10 + scale, d0, d1, col)


# ------------------------------------------------------------------ roofs
def make_roof(g, st, r, kind, axis="x"):
    tag = UPPER if r.upper else ROOF
    x0, x1, z0, z1, top = r.x0, r.x1, r.z0, r.z1, r.top
    era = st["era"]
    if kind == "gable":
        ov = 0.4
        # ridge along x: slope across z (axis "x"), or along z
        if axis == "x":
            lo_a, hi_a, lo_b, hi_b = x0 - 0.3, x1 + 0.3, z0 - ov, z1 + ov
        else:
            lo_a, hi_a, lo_b, hi_b = z0 - 0.3, z1 + 0.3, x0 - ov, x1 + ov
        half = (hi_b - lo_b) / 2
        rise = half * 0.5
        if axis == "x":
            s, X, Y, Z = g.region(lo_a, hi_a, top - 0.2, top + rise + 0.4, lo_b, hi_b)
            A, B = X, Z
        else:
            s, X, Y, Z = g.region(lo_b, hi_b, top - 0.2, top + rise + 0.4, lo_a, hi_a)
            A, B = Z, X
        d = np.minimum(B - lo_b, hi_b - B)                       # distance from the eave
        step = np.floor(d * 10 / 2 + 1e-6) / 10                   # 1 voxel up per 2 across
        ys = top - 0.2 + step
        roofm = (Y >= ys) & (Y < ys + 0.2)
        a10 = np.floor(A * 10 + 1e-6).astype(np.int64)
        col = np.where(h01(np.floor_divide(a10, 8), 11) < 0.6, st["roof"][0], st["roof"][1])
        ridge = (half - d) < 0.25
        col = np.where(ridge, st["roof_cap"], col)
        roofm = np.broadcast_to(roofm, g.col[s].shape)
        g.put_mask(s, roofm, 0, tag)  # placeholder to set tags below
        sub_c, sub_t = g.col[s], g.tag[s]
        sub_c[roofm] = np.broadcast_to(col, roofm.shape)[roofm]
        sub_t[roofm] = tag
        # gable ends: wall planks filling the triangle under the roof
        wtag = UPPER if r.upper else ROOF
        if axis == "x":
            for (ga, gb) in ((x0, x0 + T), (x1 - T, x1)):
                s2, X2, Y2, Z2 = g.region(ga, gb, top, top + rise + 0.2, z0, z1)
                d2 = np.minimum(Z2 - (z0 - ov), (z1 + ov) - Z2)
                fill = (Y2 >= top) & (Y2 < top - 0.2 + np.floor(d2 * 10 / 2 + 1e-6) / 10)
                pat = wall_pattern(st, X2, Y2, Z2, "px", top, 3.0, r.shed)
                fill = np.broadcast_to(fill, g.col[s2].shape)
                sc, stg = g.col[s2], g.tag[s2]
                sc[fill] = np.broadcast_to(pat, fill.shape)[fill]
                stg[fill] = wtag
                # round attic vent
                cz = (z0 + z1) / 2
                g.box(ga - 0.1 if ga == x0 else gb, ga if ga == x0 else gb + 0.1, top + 0.4, top + 0.8,
                      cz - 0.2, cz + 0.2, st["frame"], wtag)
        else:
            for (ga, gb) in ((z0, z0 + T), (z1 - T, z1)):
                s2, X2, Y2, Z2 = g.region(x0, x1, top, top + rise + 0.2, ga, gb)
                d2 = np.minimum(X2 - (x0 - ov), (x1 + ov) - X2)
                fill = (Y2 >= top) & (Y2 < top - 0.2 + np.floor(d2 * 10 / 2 + 1e-6) / 10)
                pat = wall_pattern(st, X2, Y2, Z2, "pz", top, 3.0, r.shed)
                fill = np.broadcast_to(fill, g.col[s2].shape)
                sc, stg = g.col[s2], g.tag[s2]
                sc[fill] = np.broadcast_to(pat, fill.shape)[fill]
                stg[fill] = wtag
        # gutters on the eaves + bulb string on the front eave
        if axis == "x":
            for zz in (z0 - ov, z1 + ov - 0.1):
                g.box(x0 - 0.3, x1 + 0.3, top - 0.3, top - 0.2, zz, zz + 0.1, st["metal"], tag)
            for x in np.arange(x0 + 0.2, x1 - 0.1, 0.6):
                xx = round(x * 10) / 10
                g.box(xx, xx + 0.1, top - 0.5, top - 0.3, z1 + ov - 0.1, z1 + ov, C["warm_glow"], tag)
            # stove pipe
            px, pz = x1 - 1.6, (z0 + z1) / 2 - 1.0
            g.box(px, px + 0.3, top, top + rise + 1.0, pz, pz + 0.3, st["metal_dk"], tag)
            g.box(px - 0.1, px + 0.4, top + rise + 1.0, top + rise + 1.1, pz - 0.1, pz + 0.4, st["metal_dk"], tag)
        return
    if kind == "sawtooth":
        tooth, rise = 3.5, 1.6
        s, X, Y, Z = g.region(x0 - 0.1, x1 + 0.1, top, top + rise + 0.4, z0 - 0.2, z1 + 0.2)
        u = (X - x0) % tooth
        run = tooth - 0.3
        step = np.floor(np.minimum(u, run) * 10 * rise / run + 1e-6) / 10
        surf = (Y >= top + step) & (Y < top + step + 0.2) & (u < run)
        glass = (u >= run) & (Y < top + rise + 0.2)
        z10 = np.floor(Z * 10 + 1e-6).astype(np.int64)
        col = np.where(h01(np.floor_divide(z10, 8), 13) < 0.6, st["roof"][0], st["roof"][1])
        surf = np.broadcast_to(surf, g.col[s].shape)
        glass = np.broadcast_to(glass, g.col[s].shape)
        sc, stg = g.col[s], g.tag[s]
        sc[surf] = np.broadcast_to(col, surf.shape)[surf]
        stg[surf] = tag
        sc[glass] = st["glass_dim"]
        stg[glass] = tag
        # mullions on the glass faces and the triangle ends
        for xa in np.arange(x0 + run, x1, tooth):
            for zz in np.arange(z0, z1, 1.0):
                g.box(xa, xa + 0.3, top, top + rise + 0.2, zz, zz + 0.1, st["frame"], tag)
        for (za, zb) in ((z0 - 0.2, z0 + T), (z1 - T, z1 + 0.2)):
            s2, X2, Y2, Z2 = g.region(x0, x1, top, top + rise + 0.2, za, zb)
            u2 = (X2 - x0) % tooth
            st2 = np.floor(np.minimum(u2, run) * 10 * rise / run + 1e-6) / 10
            fill = (Y2 < top + st2) & (u2 < run)
            pat = wall_pattern(st, X2, Y2, Z2, "pz", top, 3.0, r.shed)
            fill = np.broadcast_to(fill, g.col[s2].shape)
            sc2, stg2 = g.col[s2], g.tag[s2]
            sc2[fill] = np.broadcast_to(pat, fill.shape)[fill]
            stg2[fill] = tag
        return
    # flat roofs
    if kind == "parapet":
        g.box(x0, x1, top, top + 0.2, z0, z1, st["roof"][0], tag)
        for (a0, a1, b0, b1) in ((x0, x1, z0, z0 + 0.3), (x0, x1, z1 - 0.3, z1), (x0, x0 + 0.3, z0, z1),
                                 (x1 - 0.3, x1, z0, z1)):
            s2, X2, Y2, Z2 = g.region(a0, a1, top, top + 0.6, b0, b1)
            pat = wall_pattern(st, X2, Y2, Z2, "pz" if b1 - b0 < 0.5 else "px", top, 1.0, r.shed)
            g.col[s2] = np.broadcast_to(pat, g.col[s2].shape)
            g.tag[s2] = tag
        g.box(x0 - 0.1, x1 + 0.1, top + 0.6, top + 0.7, z0 - 0.1, z1 + 0.1, st["roof_cap"], tag)
        g.clear(x0 + 0.3, x1 - 0.3, top + 0.6, top + 0.7, z0 + 0.3, z1 - 0.3)
        # gravel speckle
        s3, X3, Y3, Z3 = g.region(x0 + 0.3, x1 - 0.3, top + 0.1, top + 0.2, z0 + 0.3, z1 - 0.3)
        sp = h01(np.floor(X3 * 10).astype(np.int64), np.floor(Z3 * 10).astype(np.int64), 9) < 0.18
        g.put_mask(s3, sp, st["roof"][1], tag, only_filled=True)
        return
    # flat (eras 3, 4) and dome (5): slab with an edge band
    g.box(x0 - 0.1, x1 + 0.1, top, top + 0.3, z0 - 0.1, z1 + 0.1, st["roof"][0], tag)
    edge = {3: C["orange"], 4: st["led"], 5: st["trim"]}.get(era, st["roof_cap"])
    if era == 3:
        g.box(x0 - 0.1, x1 + 0.1, top + 0.3, top + 0.5, z0 - 0.1, z1 + 0.1, C["white"], tag)
        g.clear(x0 + 0.1, x1 - 0.1, top + 0.3, top + 0.5, z0 + 0.1, z1 - 0.1)
        g.box(x0 - 0.2, x1 + 0.2, top + 0.1, top + 0.2, z0 - 0.2, z1 + 0.2, edge, tag)
    elif era == 4:
        g.box(x0 - 0.2, x1 + 0.2, top + 0.2, top + 0.3, z0 - 0.2, z1 + 0.2, st["roof_cap"], tag)
        g.box(x0 - 0.2, x1 + 0.2, top + 0.1, top + 0.2, z0 - 0.2, z1 + 0.2, edge, tag)
        g.clear(x0 - 0.1, x1 + 0.1, top + 0.1, top + 0.3, z0 - 0.1, z1 + 0.1)
        g.box(x0 - 0.1, x1 + 0.1, top, top + 0.3, z0 - 0.1, z1 + 0.1, st["roof"][0], tag)
    else:
        # rounded silver edge: a step-in on the top
        g.box(x0, x1, top + 0.3, top + 0.4, z0, z1, st["roof"][1], tag)
        g.box(x0 - 0.2, x1 + 0.2, top + 0.1, top + 0.2, z0 - 0.2, z1 + 0.2, edge, tag)
        g.clear(x0 - 0.1, x1 + 0.1, top + 0.1, top + 0.2, z0 - 0.1, z1 + 0.1)
        g.box(x0 - 0.1, x1 + 0.1, top, top + 0.3, z0 - 0.1, z1 + 0.1, st["roof"][0], tag)


def roof_top(r, era):
    """y of the walkable roof surface"""
    return r.top + {1: 0.0, 2: 0.2, 3: 0.3, 4: 0.3, 5: 0.4}[era]


# ------------------------------------------------------------------ prop stamps
def _sparkle(s, ac, yc, z0, z1, col, sc=0.1, axis="z"):
    n = len(STAR)
    for i, row in enumerate(STAR):
        for j, ch in enumerate(row):
            if ch == "#":
                a = ac + (j - n // 2) * sc
                y = yc + (n // 2 - i) * sc
                if axis == "z":
                    s.box(a - sc / 2, a + sc / 2, y - sc / 2, y + sc / 2, z0, z1, col)
                else:
                    s.box(z0, z1, y - sc / 2, y + sc / 2, a - sc / 2, a + sc / 2, col)


def monitor(s, st, x, z, y, w=0.6):
    """a screen facing +z standing at (x, y, z)"""
    m = st["monitor"]
    if m == "crt":
        s.box(x - 0.25, x + 0.25, y, y + 0.1, z - 0.2, z + 0.1, st["case"])
        s.box(x - 0.3, x + 0.3, y + 0.1, y + 0.5, z - 0.3, z + 0.1, st["case"])
        s.box(x - 0.2, x + 0.2, y + 0.2, y + 0.4, z + 0.1, z + 0.2, st["screen"])
    elif m == "flat":
        s.box(x - 0.05, x + 0.05, y, y + 0.2, z - 0.1, z, st["metal_dk"])
        s.box(x - w / 2, x + w / 2, y + 0.2, y + 0.6, z - 0.1, z, C["ink"])
        s.box(x - w / 2 + 0.1, x + w / 2 - 0.1, y + 0.3, y + 0.5, z, z + 0.1, st["screen"])
    else:  # holo: a floating glowing sheet over a puck
        s.box(x - 0.15, x + 0.15, y, y + 0.1, z - 0.15, z + 0.05, st["case"])
        s.box(x - w / 2, x + w / 2, y + 0.3, y + 0.7, z - 0.05, z + 0.05, st["screen"])
        s.box(x - w / 2 + 0.1, x + w / 2 - 0.1, y + 0.4, y + 0.5, z - 0.05, z + 0.05, st["screen2"])


def chair(s, st, x, z, face=-1, col=None):
    """chair whose sitter faces `face` (-1 = -z)"""
    col = col or st["chair"]
    s.box(x - 0.25, x + 0.25, 0.4, 0.5, z - 0.25, z + 0.25, col)
    bz = z + 0.25 if face < 0 else z - 0.25
    s.box(x - 0.25, x + 0.25, 0.5, 1.0, bz - 0.1 if face < 0 else bz, bz if face < 0 else bz + 0.1, col)
    s.box(x - 0.05, x + 0.05, 0.1, 0.4, z - 0.05, z + 0.05, st["metal_dk"])
    s.box(x - 0.25, x + 0.25, 0.0, 0.1, z - 0.05, z + 0.05, st["metal_dk"])
    s.box(x - 0.05, x + 0.05, 0.0, 0.1, z - 0.25, z + 0.25, st["metal_dk"])


@lru_cache(None)
def desk(era, with_chair=True, variant=0):
    st = STYLES[era]
    s = Stamp(1.8, 1.4, 1.6)
    s.box(-0.8, 0.8, 0.7, 0.8, -0.7, 0.1, st["desk_top"])
    s.box(-0.8, -0.7, 0.0, 0.7, -0.7, 0.1, st["desk"])
    s.box(0.3, 0.8, 0.0, 0.7, -0.7, 0.1, st["desk"])          # drawer block
    for y in (0.2, 0.45):
        s.box(0.4, 0.7, y, y + 0.1, 0.1, 0.2, st["metal"])
    s.box(-0.7, 0.3, 0.3, 0.7, -0.7, -0.6, st["desk"])         # modesty panel
    monitor(s, st, -0.15 if variant % 2 == 0 else 0.1, -0.4, 0.8)
    s.box(-0.4, 0.1, 0.8, 0.9, -0.1, 0.1, C["grey_lt"] if era > 2 else st["case"])   # keyboard
    s.box(0.5, 0.6, 0.8, 1.0, -0.3, -0.2, (C["red"], C["orange"], C["blue_lt"])[variant % 3])  # mug
    if variant % 2 == 0:
        s.box(0.35, 0.75, 0.8, 0.9, -0.6, -0.3, C["paper"])
        s.box(0.4, 0.7, 0.9, 1.0, -0.55, -0.35, C["paper"])
    else:
        s.box(-0.7, -0.5, 0.8, 0.9, -0.6, -0.4, C["pot"])
        s.box(-0.7, -0.5, 0.9, 1.2, -0.6, -0.4, C["leaf"])
        s.box(-0.8, -0.4, 1.1, 1.2, -0.6, -0.4, C["leaf3"])
    if with_chair:
        chair(s, st, -0.1, 0.45, -1)
    return s


@lru_cache(None)
def console(era, width=2.4, screens=3):
    """mission-control console, the operator stands/sits on +z"""
    st = STYLES[era]
    s = Stamp(width, 1.6, 1.2)
    hw = width / 2
    s.box(-hw, hw, 0.0, 0.7, -0.5, 0.2, st["cab"])
    s.box(-hw, hw, 0.7, 0.8, -0.5, 0.4, st["desk_top"] if era != 4 else st["metal_dk"])
    s.box(-hw, hw, 0.8, 1.4, -0.5, -0.3, st["cab"])
    w = (width - 0.2) / screens
    for i in range(screens):
        x = -hw + 0.1 + i * w
        col = (st["screen"], st["screen2"], C["screen_land"])[i % 3]
        s.box(x + 0.05, x + w - 0.05, 0.9, 1.35, -0.3, -0.2, col)
        s.box(x + 0.15, x + w - 0.15, 1.05, 1.1, -0.2, -0.15, C["white_glow"] if i % 2 else st["screen2"])
    # button rows
    for i, x in enumerate(np.arange(-hw + 0.2, hw - 0.1, 0.2)):
        col = (C["red_glow"], C["green_glow"], C["amber_glow"], C["teal_glow"])[i % 4]
        s.box(x, x + 0.1, 0.8, 0.9, 0.1, 0.2, col)
    s.box(-hw, hw, 0.0, 0.1, 0.2, 0.3, st["metal_dk"])
    if era == 4:
        s.box(-hw, hw, 0.1, 0.2, 0.2, 0.3, st["led"])
    return s


@lru_cache(None)
def lab_bench(era, variant=0):
    st = STYLES[era]
    s = Stamp(2.4, 1.8, 1.0)
    s.box(-1.2, 1.2, 0.0, 0.8, -0.5, 0.3, st["cab"])
    for x in (-0.9, -0.3, 0.3, 0.9):
        s.box(x - 0.2, x + 0.2, 0.3, 0.4, 0.3, 0.4, st["metal"])
    s.box(-1.2, 1.2, 0.8, 0.9, -0.5, 0.4, C["ink"] if era < 3 else C["white"])
    s.box(-1.2, 1.2, 0.9, 1.6, -0.5, -0.4, st["metal_dk"])
    s.box(-1.2, 1.2, 1.3, 1.4, -0.5, -0.2, st["desk_top"])          # reagent shelf
    flask = [C["green_glow"], C["pink_glow"], C["teal_glow"], C["amber_glow"], C["violet_glow"], C["ice_glow"]]
    for i, x in enumerate(np.arange(-1.1, 1.1, 0.3)):
        c = flask[(i + variant) % len(flask)]
        s.box(x, x + 0.1, 1.4, 1.6, -0.4, -0.3, c)
        s.box(x, x + 0.1, 1.6, 1.7, -0.4, -0.3, C["white"])
    # flasks and a microscope on the top
    s.box(-0.9, -0.7, 0.9, 1.0, -0.2, 0.0, flask[variant % 6])
    s.box(-0.85, -0.75, 1.0, 1.2, -0.15, -0.05, flask[variant % 6])
    s.box(-0.5, -0.4, 0.9, 1.1, -0.2, -0.1, flask[(variant + 2) % 6])
    s.box(0.4, 0.8, 0.9, 1.0, -0.3, 0.1, st["metal_dk"])            # microscope
    s.box(0.5, 0.6, 1.0, 1.4, -0.3, -0.2, st["metal_dk"])
    s.box(0.5, 0.6, 1.3, 1.4, -0.2, 0.0, st["metal_dk"])
    s.box(0.5, 0.6, 1.4, 1.5, -0.1, 0.0, C["black"])
    s.box(-0.2, 0.2, 0.9, 1.0, -0.1, 0.2, C["paper"])
    return s


@lru_cache(None)
def fume_hood(era):
    st = STYLES[era]
    s = Stamp(1.6, 2.4, 1.0)
    s.box(-0.8, 0.8, 0.0, 0.9, -0.5, 0.3, st["cab"])
    s.box(-0.8, 0.8, 0.9, 2.2, -0.5, -0.3, st["metal"])
    s.box(-0.8, -0.7, 0.9, 2.2, -0.5, 0.3, st["metal"])
    s.box(0.7, 0.8, 0.9, 2.2, -0.5, 0.3, st["metal"])
    s.box(-0.8, 0.8, 1.9, 2.4, -0.5, 0.3, st["metal"])
    s.box(-0.7, 0.7, 1.0, 1.8, 0.2, 0.3, C["ice_glow"])
    s.box(-0.7, 0.7, 1.3, 1.4, 0.2, 0.3, st["metal"])
    s.box(-0.5, -0.3, 0.9, 1.1, -0.2, 0.0, C["green_glow"])
    s.box(0.2, 0.4, 0.9, 1.2, -0.2, 0.0, C["pink_glow"])
    return s


@lru_cache(None)
def workbench(era, variant=0):
    st = STYLES[era]
    s = Stamp(2.2, 2.4, 1.0)
    top = st["desk_top"] if era <= 2 else st["metal"]
    s.box(-1.0, 1.0, 0.8, 0.9, -0.5, 0.3, top)
    for x in (-0.95, 0.85):
        s.box(x, x + 0.1, 0.0, 0.8, -0.5, -0.4, st["desk"])
        s.box(x, x + 0.1, 0.0, 0.8, 0.2, 0.3, st["desk"])
    s.box(-1.0, 1.0, 0.2, 0.3, -0.5, 0.3, st["desk"])                  # lower shelf
    s.box(-0.8, -0.2, 0.3, 0.6, -0.4, 0.1, C["red"])                    # toolbox
    s.box(-0.8, -0.2, 0.6, 0.7, -0.2, -0.1, C["grey_dk"])
    s.box(0.2, 0.5, 0.3, 0.5, -0.3, 0.1, C["crate"])
    # pegboard with tools
    s.box(-1.0, 1.0, 0.9, 2.2, -0.5, -0.4, st["cab"] if era > 1 else C["crate2"])
    tools = [C["red"], C["orange"], C["grey"], C["yellow"], C["blue_lt"], C["grey_dk"]]
    for i, x in enumerate(np.arange(-0.85, 0.9, 0.25)):
        c = tools[(i + variant) % len(tools)]
        hh = 0.3 + 0.1 * ((i * 7 + variant) % 3)
        s.box(x, x + 0.1, 1.7 - hh, 1.8, -0.4, -0.3, c)
        if i % 2 == 0:
            s.box(x - 0.05, x + 0.15, 1.7, 1.8, -0.4, -0.3, c)
    s.box(-0.9, 0.9, 1.95, 2.05, -0.4, -0.3, st["metal_dk"])
    # vise and lamp
    s.box(0.5, 0.8, 0.9, 1.1, -0.1, 0.2, C["blue"])
    s.box(0.55, 0.75, 1.1, 1.2, 0.0, 0.1, C["grey_dk"])
    s.box(-0.1, 0.0, 0.9, 1.5, -0.3, -0.2, st["metal_dk"])
    s.box(-0.2, 0.1, 1.4, 1.5, -0.3, 0.0, st["metal_dk"])
    s.box(-0.15, 0.05, 1.35, 1.4, -0.2, -0.0, st["lamp"])
    return s


@lru_cache(None)
def shelf(era, variant=0, width=1.6, height=2.0):
    st = STYLES[era]
    s = Stamp(width, height, 0.6)
    hw = width / 2
    frame = st["desk"] if era <= 2 else st["metal_dk"]
    s.box(-hw, -hw + 0.1, 0.0, height, -0.3, 0.2, frame)
    s.box(hw - 0.1, hw, 0.0, height, -0.3, 0.2, frame)
    s.box(-hw, hw, 0.0, height, -0.3, -0.2, st["cab"])
    items = [C["red"], C["blue"], C["yellow"], C["leaf"], C["orange"], C["paper"], C["violet"], C["teal"],
             C["crate"], C["grey_lt"]]
    nsh = int(height / 0.5)
    for k in range(nsh):
        y = k * 0.5
        s.box(-hw, hw, y, y + 0.1, -0.3, 0.2, frame)
        x = -hw + 0.1
        i = 0
        while x < hw - 0.2:
            w = 0.1 * (1 + (k * 3 + i * 5 + variant) % 3)
            hh = 0.2 + 0.1 * ((k + i * 2 + variant) % 3)
            if (k + i + variant) % 5 != 4:
                s.box(x, min(x + w, hw - 0.1), y + 0.1, y + 0.1 + hh, -0.2, 0.1, items[(k * 4 + i + variant) % len(items)])
            x += w + (0.1 if (i + k) % 3 == 0 else 0)
            i += 1
    s.box(-hw, hw, height - 0.1, height, -0.3, 0.2, frame)
    return s


@lru_cache(None)
def plant(size=1, variant=0):
    s = Stamp(1.0, 2.2, 1.0)
    pot = (C["pot"], C["pot2"], C["white"], C["blue"])[variant % 4]
    leaves = (C["leaf"], C["leaf2"], C["leaf3"])
    if size == 0:
        s.box(-0.15, 0.15, 0.0, 0.3, -0.15, 0.15, pot)
        s.box(-0.1, 0.1, 0.3, 0.6, -0.1, 0.1, leaves[variant % 3])
        s.box(-0.2, 0.2, 0.4, 0.5, -0.1, 0.1, leaves[(variant + 1) % 3])
        return s
    s.box(-0.25, 0.25, 0.0, 0.5, -0.25, 0.25, pot)
    s.box(-0.3, 0.3, 0.4, 0.5, -0.3, 0.3, pot)
    s.box(-0.2, 0.2, 0.45, 0.5, -0.2, 0.2, C["soil"])
    s.sphere(0.0, 1.1 if size == 2 else 0.9, 0.0, 0.42 if size == 2 else 0.35, leaves[variant % 3])
    s.sphere(0.15, 1.45 if size == 2 else 1.1, 0.1, 0.28, leaves[(variant + 1) % 3])
    s.sphere(-0.2, 1.3 if size == 2 else 1.0, -0.1, 0.25, leaves[(variant + 2) % 3])
    s.box(-0.05, 0.05, 0.5, 0.8, -0.05, 0.05, C["crate_dk"])
    return s


@lru_cache(None)
def crate(variant=0, size=0.8):
    s = Stamp(size + 0.2, size + 0.2, size + 0.2)
    h = size / 2
    c1, c2 = ((C["crate"], C["crate_dk"]), (C["crate2"], C["crate_dk"]), (C["grey"], C["grey_dk"]),
              (C["blue"], C["ink"]))[variant % 4]
    s.box(-h, h, 0.0, size, -h, h, c1)
    for (a, b) in ((-h, -h + 0.1), (h - 0.1, h)):
        s.box(a, b, 0.0, size, -h - 0.0, -h + 0.1, c2)
        s.box(a, b, 0.0, size, h - 0.1, h, c2)
    s.box(-h, h, size - 0.1, size, -h, -h + 0.1, c2)
    s.box(-h, h, size - 0.1, size, h - 0.1, h, c2)
    s.box(-h, h, 0.0, 0.1, h - 0.1, h + 0.0, c2)
    if variant % 2 == 0:
        s.box(-0.1, 0.1, size * 0.4, size * 0.4 + 0.2, h, h + 0.05, C["orange"])
    return s


@lru_cache(None)
def barrel(variant=0):
    s = Stamp(0.8, 1.0, 0.8)
    c = (C["barrel"], C["barrel2"], C["yellow"], C["grey"])[variant % 4]
    s.cyl_y(0.0, 0.0, 0.32, 0.0, 0.9, c)
    s.cyl_y(0.0, 0.0, 0.34, 0.2, 0.3, C["grey_dk"])
    s.cyl_y(0.0, 0.0, 0.34, 0.6, 0.7, C["grey_dk"])
    s.cyl_y(0.0, 0.0, 0.22, 0.9, 1.0, c)
    return s


@lru_cache(None)
def lockers(era, n=4):
    st = STYLES[era]
    s = Stamp(n * 0.5, 2.0, 0.6)
    hw = n * 0.25
    cols = [st["accent"] if era != 4 else C["teal"], st["cab"]]
    for i in range(n):
        x = -hw + i * 0.5
        c = cols[i % 2] if era in (3, 4, 5) else (C["blue"], C["fabric_g"])[i % 2]
        s.box(x, x + 0.5, 0.1, 1.8, -0.3, 0.2, c)
        s.box(x, x + 0.05, 0.1, 1.8, 0.2, 0.25, st["metal_dk"])
        for y in (1.4, 1.5, 1.6):
            s.box(x + 0.1, x + 0.4, y, y + 0.05, 0.2, 0.25, st["metal_dk"])
        s.box(x + 0.35, x + 0.45, 0.9, 1.1, 0.2, 0.3, C["grey_lt"])
    s.box(-hw, hw, 0.0, 0.1, -0.3, 0.2, C["ink"])
    s.box(-hw, hw, 1.8, 1.9, -0.3, 0.2, st["metal_dk"])
    s.box(-hw + 0.2, -hw + 0.6, 1.9, 2.0, -0.2, 0.1, C["fabric_r"])
    return s


@lru_cache(None)
def sofa(era, width=2.0):
    st = STYLES[era]
    s = Stamp(width + 0.2, 1.0, 1.0)
    hw = width / 2
    c = st["sofa"]
    s.box(-hw, hw, 0.1, 0.45, -0.4, 0.4, c)
    s.box(-hw, hw, 0.45, 0.9, -0.4, -0.2, c)
    s.box(-hw, -hw + 0.2, 0.45, 0.65, -0.4, 0.4, c)
    s.box(hw - 0.2, hw, 0.45, 0.65, -0.4, 0.4, c)
    for x in np.arange(-hw + 0.3, hw - 0.3, 0.6):
        s.box(x, x + 0.5, 0.45, 0.5, -0.2, 0.35, C["paper"] if era == 1 else st["chair2"])
    s.box(-hw + 0.3, -hw + 0.6, 0.5, 0.8, -0.2, -0.1, C["flower_y"])
    s.box(-hw, hw, 0.0, 0.1, -0.4, 0.4, C["ink"])
    return s


@lru_cache(None)
def coffee_corner(era):
    st = STYLES[era]
    s = Stamp(2.0, 2.2, 0.8)
    s.box(-1.0, 1.0, 0.0, 0.9, -0.4, 0.2, st["cab"])
    s.box(-1.0, 1.0, 0.9, 1.0, -0.4, 0.3, st["desk_top"])
    s.box(-0.8, -0.3, 1.0, 1.6, -0.35, 0.0, C["black"] if era != 5 else C["white"])   # machine
    s.box(-0.7, -0.4, 1.3, 1.5, 0.0, 0.05, C["red_glow"] if era < 4 else st["screen"])
    s.box(-0.65, -0.45, 1.0, 1.1, -0.1, 0.1, C["white"])
    for i, x in enumerate((0.0, 0.2, 0.4)):
        s.box(x, x + 0.1, 1.0, 1.1, -0.1, 0.0, (C["red"], C["white"], C["orange"])[i])
    s.box(0.6, 0.9, 1.0, 1.4, -0.3, 0.0, C["crate"])          # cookie jar
    s.box(0.6, 0.9, 1.4, 1.5, -0.3, 0.0, C["pot"])
    # water cooler next to it
    s.box(-1.0, 1.0, 1.7, 2.1, -0.4, -0.3, st["cab"])           # wall cupboard
    s.box(-1.0, 1.0, 1.6, 1.7, -0.4, 0.0, st["desk"])
    return s


@lru_cache(None)
def water_cooler(era):
    s = Stamp(0.6, 1.6, 0.6)
    s.box(-0.2, 0.2, 0.0, 0.9, -0.2, 0.2, C["white"])
    s.box(-0.1, 0.1, 0.6, 0.7, 0.2, 0.25, C["blue_lt"])
    s.cyl_y(0.0, 0.0, 0.18, 0.9, 1.5, P("#9fd0ff", 0.6))
    return s


@lru_cache(None)
def meeting_table(era, length=3.2, chairs=True):
    st = STYLES[era]
    s = Stamp(1.6 + 1.2, 1.0, length + 0.4)
    hl = length / 2
    s.box(-0.6, 0.6, 0.7, 0.8, -hl, hl, st["desk_top"])
    s.box(-0.3, 0.3, 0.0, 0.7, -hl + 0.3, -hl + 0.5, st["desk"])
    s.box(-0.3, 0.3, 0.0, 0.7, hl - 0.5, hl - 0.3, st["desk"])
    if chairs:
        for z in np.arange(-hl + 0.6, hl - 0.4, 0.9):
            for side in (-1, 1):
                x = side * 0.9
                s.box(x - 0.25, x + 0.25, 0.4, 0.5, z - 0.25, z + 0.25, st["chair"])
                bx = x + side * 0.25
                s.box(min(bx, bx - side * 0.1), max(bx, bx - side * 0.1), 0.5, 1.0, z - 0.25, z + 0.25, st["chair"])
                s.box(x - 0.05, x + 0.05, 0.0, 0.4, z - 0.05, z + 0.05, st["metal_dk"])
    for i, z in enumerate(np.arange(-hl + 0.6, hl - 0.4, 0.9)):
        s.box(-0.4, -0.1, 0.8, 0.85, z - 0.15, z + 0.15, C["paper"])
        s.box(0.2, 0.3, 0.8, 1.0, z, z + 0.1, (C["red"], C["blue_lt"], C["orange"])[i % 3])
    s.box(-0.1, 0.1, 0.8, 1.1, -0.1, 0.1, C["leaf"])
    return s


@lru_cache(None)
def whiteboard(era, variant=0, width=2.0):
    """wall-mounted (back against -z), 0.2 deep"""
    st = STYLES[era]
    s = Stamp(width + 0.2, 2.4, 0.4)
    hw = width / 2
    s.box(-hw - 0.1, hw + 0.1, 0.9, 2.2, -0.2, -0.1, st["metal_dk"] if era > 1 else C["crate_dk"])
    s.box(-hw, hw, 1.0, 2.1, -0.1, 0.0, C["white"] if era != 1 else C["ink"])   # chalkboard in era 1
    ink = [C["blue"], C["red"], C["leaf2"], C["orange"]] if era != 1 else [C["white"], C["paper"], C["flower_y"]]
    # scribbles: an orbit, a rocket, a bar chart (no text)
    for i in range(12):
        a = i / 12 * math.tau
        x = -hw * 0.45 + math.cos(a) * 0.45
        y = 1.55 + math.sin(a) * 0.3
        s.box(round(x, 1), round(x, 1) + 0.1, round(y, 1), round(y, 1) + 0.1, 0.0, 0.05, ink[0])
    s.box(-hw * 0.45 - 0.1, -hw * 0.45 + 0.1, 1.45, 1.65, 0.0, 0.05, ink[3 % len(ink)])
    for i, hh in enumerate((0.3, 0.5, 0.4, 0.7)):
        x = 0.2 + i * 0.2
        s.box(x, x + 0.1, 1.2, 1.2 + hh, 0.0, 0.05, ink[(i + variant) % len(ink)])
    s.box(0.1, 0.1 + 0.9, 1.15, 1.2, 0.0, 0.05, ink[1])
    s.box(-hw, hw, 0.95, 1.0, -0.1, 0.1, st["metal"])
    s.box(-0.3, -0.1, 1.0, 1.05, 0.0, 0.1, ink[1])
    return s


@lru_cache(None)
def poster(era, variant=0):
    """wall poster 1.0 x 1.4 (back against -z)"""
    st = STYLES[era]
    s = Stamp(1.2, 2.6, 0.2)
    bg = (C["ink"], P("#24324d"), st["accent"] if era != 3 else C["blue"], C["dark"])[variant % 4]
    s.box(-0.5, 0.5, 1.1, 2.5, -0.1, 0.0, bg)
    if variant % 2 == 0:  # rocket poster
        for i, row in enumerate(ROCKET_ICON):
            for j, ch in enumerate(row):
                if ch == ".":
                    continue
                c = {"#": C["white"], "o": C["blue_lt"], "f": C["orange"]}[ch]
                x = (j - 2.5) * 0.1
                y = 2.3 - i * 0.12
                s.box(round(x, 1), round(x, 1) + 0.1, round(y, 1), round(y, 1) + 0.1, 0.0, 0.05, c)
        s.box(-0.4, 0.4, 1.2, 1.3, 0.0, 0.05, C["orange"])
    else:  # planet + moon poster
        s.box(-0.3, 0.1, 1.5, 1.9, 0.0, 0.05, C["blue_lt"])
        s.box(-0.2, 0.0, 1.6, 1.7, 0.0, 0.06, C["leaf3"])
        s.box(0.2, 0.3, 2.1, 2.2, 0.0, 0.05, C["grey_lt"])
        _sparkle(s, 0.25, 1.35, 0.0, 0.05, C["yellow"], sc=0.05)
    return s


@lru_cache(None)
def rug(era, w=2.4, d=1.6):
    st = STYLES[era]
    s = Stamp(w, 0.2, d)
    s.box(-w / 2, w / 2, 0.0, 0.1, -d / 2, d / 2, st["rug"][0])
    s.box(-w / 2 + 0.2, w / 2 - 0.2, 0.0, 0.1, -d / 2 + 0.2, d / 2 - 0.2, st["rug"][1])
    s.box(-w / 2 + 0.3, w / 2 - 0.3, 0.0, 0.1, -d / 2 + 0.3, d / 2 - 0.3, st["rug"][0])
    return s


@lru_cache(None)
def reception(era):
    st = STYLES[era]
    s = Stamp(3.2, 1.6, 1.4)
    s.box(-1.4, 1.4, 0.0, 1.1, 0.0, 0.4, st["desk"])
    s.box(-1.5, 1.5, 1.1, 1.2, -0.1, 0.5, st["desk_top"])
    s.box(-1.4, -1.0, 0.0, 1.1, -0.6, 0.0, st["desk"])
    s.box(1.0, 1.4, 0.0, 1.1, -0.6, 0.0, st["desk"])
    _sparkle(s, 0.0, 0.6, 0.4, 0.5, C["orange"] if era != 4 else st["led"], sc=0.1)
    monitor(s, st, -0.6, -0.1, 1.2, w=0.5)
    s.box(0.5, 0.7, 1.2, 1.4, 0.0, 0.2, C["leaf"])
    s.box(0.8, 1.0, 1.2, 1.3, 0.1, 0.3, C["red_glow"])            # the bell
    return s


@lru_cache(None)
def rocket_h(era, length=5.0, r=0.8):
    """a rocket stage lying on two cradles, axis along x"""
    s = Stamp(length + 1.0, 2 * r + 0.8, 2 * r + 0.6)
    hl = length / 2
    cy = r + 0.5
    s.cyl_x(cy, 0.0, r, -hl, hl, C["rocket"])
    s.cyl_x(cy, 0.0, r + 0.05, -hl + 0.8, -hl + 1.2, C["orange"])
    s.cyl_x(cy, 0.0, r + 0.05, hl - 1.4, hl - 1.2, C["ink"])
    s.cyl_x(cy, 0.0, r * 0.6, hl, hl + 0.2, C["grey_dk"])
    # engine bell at -x end
    X, Y, Z = s.coords()
    R = np.sqrt((Y - cy) ** 2 + Z ** 2)
    t = (-hl - X) / 0.5
    bell = (X < -hl) & (X > -hl - 0.5) & (R < r * 0.35 + t * r * 0.3) & (R > r * 0.35 + t * r * 0.3 - 0.12)
    s.mask(bell, C["nozzle"])
    for x in (-hl + 0.8, hl - 0.9):
        s.box(x - 0.2, x + 0.2, 0.0, cy - r * 0.5, -r - 0.2, r + 0.2, C["hazard"])
        s.box(x - 0.2, x + 0.2, 0.0, 0.2, -r - 0.3, r + 0.3, C["grey_dk"])
    for i, x in enumerate(np.arange(-hl + 1.6, hl - 1.6, 0.5)):
        s.box(x, x + 0.1, cy + r - 0.05, cy + r + 0.05, -0.1, 0.1, C["grey_lt"])
    return s


@lru_cache(None)
def rocket_v(era, height=8.0, r=0.9):
    s = Stamp(2 * r + 0.6, height + 2.6, 2 * r + 0.6)
    s.cyl_y(0, 0, r, 0.4, height, C["rocket"])
    s.cyl_y(0, 0, r + 0.05, height * 0.35, height * 0.35 + 0.4, C["orange"])
    s.cyl_y(0, 0, r + 0.05, height * 0.75, height * 0.75 + 0.2, C["ink"])
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    yy = (Y - height) / 2.4
    nose = (Y >= height) & (R <= r * np.sqrt(np.clip(1 - yy ** 2, 0, 1)) * (1 - 0.3 * yy))
    s.mask(nose, C["orange"])
    s.cyl_y(0, 0, r * 0.7, 0.0, 0.4, C["nozzle"])
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        fx, fz = math.cos(ang), math.sin(ang)
        for k in range(8):
            rr = r + k * 0.06
            s.box(fx * rr - 0.05, fx * rr + 0.05, 0.4, 1.6 - k * 0.12, fz * rr - 0.05, fz * rr + 0.05, C["orange_dk"])
    return s


@lru_cache(None)
def engine_stand(era):
    s = Stamp(1.6, 2.2, 1.6)
    s.box(-0.7, 0.7, 0.0, 0.3, -0.7, 0.7, C["hazard"])
    s.box(-0.6, 0.6, 0.3, 0.4, -0.6, 0.6, C["grey_dk"])
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    t = (1.3 - Y) / 0.9
    bell = (Y > 0.4) & (Y < 1.3) & (R < 0.18 + t * 0.4) & (R > 0.08 + t * 0.4)
    s.mask(bell, C["nozzle"])
    s.cyl_y(0, 0, 0.28, 1.3, 1.7, P("#b06a3e"))
    s.cyl_y(0, 0, 0.18, 1.7, 2.0, C["grey"])
    s.box(0.2, 0.4, 1.4, 1.9, -0.1, 0.1, C["grey_lt"])
    s.box(-0.4, -0.2, 1.5, 1.8, -0.1, 0.1, P("#b06a3e"))
    return s


@lru_cache(None)
def tool_cart(era, variant=0):
    s = Stamp(1.0, 1.2, 0.8)
    c = (C["red"], C["blue"], C["orange"])[variant % 3]
    s.box(-0.4, 0.4, 0.15, 0.9, -0.25, 0.25, c)
    for y in (0.35, 0.55, 0.75):
        s.box(-0.35, 0.35, y, y + 0.05, 0.25, 0.3, C["grey_lt"])
    s.box(-0.45, 0.45, 0.9, 1.0, -0.3, 0.3, C["grey_dk"])
    s.box(-0.2, 0.2, 1.0, 1.1, -0.1, 0.1, C["yellow"])
    for x in (-0.35, 0.25):
        for z in (-0.2, 0.1):
            s.box(x, x + 0.1, 0.0, 0.15, z, z + 0.1, C["rubber"])
    return s


@lru_cache(None)
def telescope(era):
    st = STYLES[era]
    s = Stamp(2.6, 3.6, 2.6)
    s.cyl_y(0, 0, 0.5, 0.0, 0.3, st["metal_dk"])
    s.box(-0.2, 0.2, 0.3, 1.4, -0.2, 0.2, st["metal_dk"])
    s.box(-0.5, 0.5, 1.3, 1.6, -0.15, 0.15, st["metal_dk"])
    # tilted tube (45 deg up towards -z)
    X, Y, Z = s.coords()
    c0 = np.array([0.0, 1.6, 0.4])
    d = np.array([0.0, 0.70, -0.71])
    rel_y, rel_z = Y - c0[1], Z - c0[2]
    t = rel_y * d[1] + rel_z * d[2]
    perp = np.sqrt(X ** 2 + (rel_y - t * d[1]) ** 2 + (rel_z - t * d[2]) ** 2)
    tube = (t > -0.6) & (t < 2.2) & (perp < 0.35)
    s.mask(tube, C["white"] if era != 4 else st["metal"])
    band = (t > 1.6) & (t < 1.9) & (perp < 0.38)
    s.mask(band, C["orange"] if era != 5 else st["accent"])
    s.mask((t > 2.1) & (t < 2.2) & (perp < 0.3), C["ice_glow"])
    s.box(0.3, 0.5, 1.6, 1.8, 0.0, 0.4, C["black"])
    return s


@lru_cache(None)
def server_rack(era, variant=0):
    st = STYLES[era]
    s = Stamp(0.8, 2.2, 1.0)
    s.box(-0.35, 0.35, 0.0, 2.0, -0.45, 0.35, C["ink"] if era != 5 else st["metal_dk"])
    lights = [C["green_glow"], C["teal_glow"], C["amber_glow"], C["red_glow"], C["ice_glow"]]
    for k, y in enumerate(np.arange(0.2, 1.9, 0.2)):
        s.box(-0.3, 0.3, y, y + 0.1, 0.35, 0.4, st["metal_dk"])
        for j, x in enumerate((-0.25, -0.1, 0.15)):
            if (k + j + variant) % 3 != 1:
                s.box(x, x + 0.1, y, y + 0.1, 0.38, 0.42, lights[(k * 2 + j + variant) % 5])
    return s


@lru_cache(None)
def vacuum_chamber(era):
    st = STYLES[era]
    s = Stamp(3.4, 3.0, 3.0)
    s.cyl_z(0.0, 1.4, 1.2, -1.2, 1.0, st["metal"])
    s.cyl_z(0.0, 1.4, 1.25, 0.9, 1.1, st["metal_dk"])
    s.cyl_z(0.0, 1.4, 0.5, 1.1, 1.2, C["ice_glow"])
    s.cyl_z(0.0, 1.4, 0.65, 1.1, 1.2, st["metal_dk"], rin=0.5)
    s.box(-1.3, 1.3, 0.0, 0.3, -1.0, 0.8, C["grey_dk"])
    s.box(1.0, 1.6, 0.3, 2.2, -0.6, 0.2, st["cab"])
    for y in (0.8, 1.2, 1.6):
        s.box(1.1, 1.5, y, y + 0.1, 0.2, 0.3, C["green_glow"] if y < 1.0 else C["amber_glow"])
    s.box(-1.5, -1.3, 0.3, 2.4, -0.1, 0.1, st["metal_dk"])
    s.box(-1.5, 0.0, 2.3, 2.5, -0.1, 0.1, st["metal_dk"])
    return s


@lru_cache(None)
def treadmill(era):
    st = STYLES[era]
    s = Stamp(1.0, 1.6, 2.0)
    s.box(-0.4, 0.4, 0.0, 0.2, -0.8, 0.8, C["rubber"])
    s.box(-0.35, 0.35, 0.2, 0.25, -0.7, 0.7, C["ink"])
    s.box(-0.45, -0.35, 0.0, 1.2, -0.8, -0.7, st["metal"])
    s.box(0.35, 0.45, 0.0, 1.2, -0.8, -0.7, st["metal"])
    s.box(-0.45, 0.45, 1.2, 1.3, -0.8, -0.5, st["metal"])
    s.box(-0.2, 0.2, 1.3, 1.5, -0.8, -0.7, st["screen"])
    return s


@lru_cache(None)
def weight_rack(era):
    st = STYLES[era]
    s = Stamp(2.0, 1.6, 0.8)
    s.box(-0.9, 0.9, 0.0, 0.1, -0.3, 0.3, st["metal_dk"])
    for x in (-0.9, 0.8):
        s.box(x, x + 0.1, 0.0, 1.2, -0.3, -0.2, st["metal_dk"])
    for y in (0.4, 0.8):
        s.box(-0.9, 0.9, y, y + 0.1, -0.3, 0.2, st["metal_dk"])
        for i, x in enumerate(np.arange(-0.7, 0.7, 0.35)):
            c = (C["red"], C["blue"], C["yellow"], C["leaf"])[i % 4]
            s.box(x, x + 0.1, y + 0.1, y + 0.3, -0.2, 0.2, C["grey_dk"])
            s.box(x - 0.1, x, y + 0.05, y + 0.35, -0.15, 0.15, c)
            s.box(x + 0.1, x + 0.2, y + 0.05, y + 0.35, -0.15, 0.15, c)
    return s


@lru_cache(None)
def punching_bag(era):
    s = Stamp(1.0, 2.8, 1.0)
    s.cyl_y(0, 0, 0.3, 0.5, 1.6, C["fabric_r"])
    s.cyl_y(0, 0, 0.32, 1.5, 1.6, C["ink"])
    s.box(-0.05, 0.05, 1.6, 2.6, -0.05, 0.05, C["grey_dk"])
    s.box(-0.3, 0.3, 0.0, 0.1, -0.3, 0.3, C["mat_blue"])
    return s


@lru_cache(None)
def climbing_wall(era, width=3.0):
    """wall-mounted (back against -z)"""
    st = STYLES[era]
    s = Stamp(width + 0.2, 3.4, 0.6)
    hw = width / 2
    s.box(-hw, hw, 0.3, 3.2, -0.3, -0.2, st["cab"] if era > 1 else C["crate2"])
    holds = [C["red"], C["yellow"], C["leaf3"], C["blue_lt"], C["orange"], C["violet"]]
    for i in range(26):
        x = -hw + 0.2 + (i * 0.37) % (width - 0.4)
        y = 0.5 + (i * 0.53) % 2.5
        s.box(round(x, 1), round(x, 1) + 0.1 + (i % 2) * 0.1, round(y, 1), round(y, 1) + 0.1 + (i % 3 == 0) * 0.1,
              -0.2, -0.1, holds[i % 6])
    s.box(-hw, hw, 0.0, 0.3, -0.3, 0.3, C["mat_blue"])
    return s


@lru_cache(None)
def gym_mat(era, w=2.0, d=1.2, variant=0):
    s = Stamp(w, 0.2, d)
    c = (C["mat_blue"], C["mat_red"], C["fabric_g"])[variant % 3]
    s.box(-w / 2, w / 2, 0.0, 0.1, -d / 2, d / 2, c)
    s.box(-w / 2, w / 2, 0.1, 0.15 if False else 0.1, -d / 2, d / 2, c)
    return s


@lru_cache(None)
def conveyor(era, length=6.0, variant=0):
    st = STYLES[era]
    s = Stamp(length, 1.6, 1.4)
    hl = length / 2
    s.box(-hl, hl, 0.7, 0.9, -0.5, 0.5, st["metal_dk"])
    s.box(-hl, hl, 0.9, 1.0, -0.4, 0.4, C["rubber"])
    for x in np.arange(-hl + 0.2, hl, 0.3):
        s.box(x, x + 0.05, 0.85, 0.95, -0.45, 0.45, st["metal"])
    for x in np.arange(-hl + 0.3, hl, 1.5):
        s.box(x, x + 0.1, 0.0, 0.7, -0.45, -0.35, st["metal_dk"])
        s.box(x, x + 0.1, 0.0, 0.7, 0.35, 0.45, st["metal_dk"])
    items = [C["crate"], C["grey_lt"], C["orange"], C["rocket"], C["blue"]]
    for i, x in enumerate(np.arange(-hl + 0.6, hl - 0.4, 1.1)):
        c = items[(i + variant) % len(items)]
        if i % 2 == 0:
            s.box(x, x + 0.5, 1.0, 1.4, -0.25, 0.25, c)
        else:
            s.cyl_x(1.25, 0.0, 0.22, x, x + 0.6, C["rocket"])
            s.cyl_x(1.25, 0.0, 0.23, x + 0.2, x + 0.3, C["orange"])
    s.box(-hl, -hl + 0.2, 1.0, 1.6, -0.5, 0.5, C["hazard"])
    s.box(hl - 0.2, hl, 1.0, 1.6, -0.5, 0.5, C["hazard"])
    s.box(-hl, -hl + 0.2, 1.5, 1.6, -0.5, 0.5, C["ink"])
    s.box(hl - 0.2, hl, 1.5, 1.6, -0.5, 0.5, C["ink"])
    return s


@lru_cache(None)
def robot_arm(era):
    st = STYLES[era]
    s = Stamp(1.6, 2.4, 1.6)
    col = C["orange"] if era == 3 else (st["accent"] if era == 5 else C["hazard"])
    s.cyl_y(0, 0, 0.4, 0.0, 0.3, C["ink"])
    s.cyl_y(0, 0, 0.3, 0.3, 0.6, col)
    s.box(-0.15, 0.15, 0.6, 1.6, -0.15, 0.15, col)
    s.box(-0.2, 0.2, 1.5, 1.8, -0.2, 0.2, C["ink"])
    s.box(-0.12, 0.12, 1.6, 1.8, 0.2, 0.9, col)
    s.box(-0.15, 0.15, 1.3, 1.6, 0.8, 1.0, C["ink"])
    s.box(-0.05, 0.05, 1.2, 1.3, 0.85, 0.95, st["led"] or C["amber_glow"])
    return s


@lru_cache(None)
def forklift(era):
    s = Stamp(1.4, 2.2, 2.2)
    c = C["hazard"] if era != 5 else C["violet"]
    s.box(-0.6, 0.6, 0.2, 0.9, -0.7, 0.6, c)
    s.box(-0.6, 0.6, 0.9, 1.0, -0.7, -0.3, C["ink"])
    for x in (-0.6, 0.5):
        s.box(x, x + 0.1, 0.9, 1.9, 0.3, 0.4, C["ink"])
        s.box(x, x + 0.1, 0.9, 1.9, -0.6, -0.5, C["ink"])
    s.box(-0.6, 0.6, 1.9, 2.0, -0.6, 0.4, C["ink"])
    s.box(-0.3, 0.3, 0.9, 1.3, -0.2, 0.1, C["ink"])
    s.box(-0.5, 0.5, 0.2, 1.8, 0.6, 0.7, C["grey_dk"])
    for x in (-0.4, 0.3):
        s.box(x, x + 0.1, 0.2, 0.3, 0.7, 1.1, C["grey_dk"])
    for (x, z) in ((-0.7, -0.6), (0.6, -0.6), (-0.7, 0.3), (0.6, 0.3)):
        s.box(x, x + 0.1, 0.0, 0.4, z - 0.1, z + 0.2, C["rubber"])
    return s


@lru_cache(None)
def pallet(variant=0):
    s = Stamp(1.2, 1.4, 1.2)
    s.box(-0.5, 0.5, 0.0, 0.15, -0.5, 0.5, C["crate"])
    if variant == 0:      # boxes
        for (x, z, y) in ((-0.45, -0.45, 0.15), (0.0, -0.45, 0.15), (-0.45, 0.0, 0.15), (0.0, 0.0, 0.15),
                          (-0.25, -0.25, 0.55)):
            s.box(x, x + 0.45, y, y + 0.4, z, z + 0.45, C["crate2"] if (x + z) < 0 else C["paper"])
    elif variant == 1:    # pipes
        for k in range(3):
            s.cyl_x(0.3 + k * 0.0, -0.3 + k * 0.3, 0.12, -0.5, 0.5, C["grey"])
    else:                 # sacks
        s.box(-0.45, 0.45, 0.15, 0.45, -0.45, 0.45, C["sand"])
        s.box(-0.35, 0.35, 0.45, 0.7, -0.35, 0.35, C["sand"])
    return s


@lru_cache(None)
def big_tank(era, length=3.6, r=1.0):
    s = Stamp(length + 0.4, 2 * r + 0.8, 2 * r + 0.6)
    hl = length / 2
    cy = r + 0.4
    s.cyl_x(cy, 0.0, r, -hl, hl, C["rocket"] if era != 4 else C["grey_lt"])
    s.cyl_x(cy, 0.0, r + 0.05, -0.1, 0.1, C["orange"])
    for x in (-hl + 0.6, hl - 0.6):
        s.box(x - 0.3, x + 0.3, 0.0, cy - r * 0.6, -r, r, C["grey_dk"])
        s.cyl_x(0.25, -r + 0.2, 0.2, x - 0.35, x + 0.35, C["rubber"])
        s.cyl_x(0.25, r - 0.2, 0.2, x - 0.35, x + 0.35, C["rubber"])
    return s


@lru_cache(None)
def floor_lamp(era):
    st = STYLES[era]
    s = Stamp(0.6, 2.0, 0.6)
    s.box(-0.2, 0.2, 0.0, 0.1, -0.2, 0.2, st["metal_dk"])
    s.box(-0.05, 0.05, 0.1, 1.6, -0.05, 0.05, st["metal_dk"])
    s.box(-0.2, 0.2, 1.5, 1.8, -0.2, 0.2, st["lamp"])
    s.box(-0.25, 0.25, 1.8, 1.9, -0.25, 0.25, st["metal_dk"] if era > 2 else C["fabric_y"])
    return s


@lru_cache(None)
def radio_desk(era):
    st = STYLES[era]
    s = Stamp(2.2, 1.8, 1.0)
    s.box(-1.0, 1.0, 0.7, 0.8, -0.45, 0.3, st["desk_top"])
    s.box(-1.0, -0.9, 0.0, 0.7, -0.45, 0.3, st["desk"])
    s.box(0.9, 1.0, 0.0, 0.7, -0.45, 0.3, st["desk"])
    for i, x in enumerate((-0.9, -0.3, 0.3)):
        s.box(x, x + 0.55, 0.8, 1.2 + 0.2 * (i % 2), -0.45, -0.1, st["case"] if era < 3 else C["ink"])
        for j in range(3):
            s.box(x + 0.05 + j * 0.15, x + 0.15 + j * 0.15, 0.95, 1.05, -0.1, -0.05,
                  (C["amber_glow"], C["green_glow"], C["red_glow"])[(i + j) % 3])
        s.box(x + 0.1, x + 0.45, 1.1, 1.15, -0.1, -0.05, st["screen"])
    s.box(-0.2, 0.0, 0.8, 0.9, 0.0, 0.2, C["ink"])                  # headset
    s.box(-0.25, 0.05, 0.9, 1.0, 0.05, 0.15, C["ink"])
    s.box(0.5, 0.7, 0.8, 0.85, -0.05, 0.25, C["paper"])
    return s


@lru_cache(None)
def big_screen(era, width=6.0, height=2.4, variant=0):
    """wall screen (back against -z): world map with an orbit and a trajectory"""
    st = STYLES[era]
    s = Stamp(width + 0.4, height + 1.6, 0.4)
    hw = width / 2
    y0 = 1.2
    frame = C["ink"] if era != 1 else C["crate_dk"]
    s.box(-hw - 0.1, hw + 0.1, y0 - 0.1, y0 + height + 0.1, -0.2, -0.1, frame)
    s.box(-hw, hw, y0, y0 + height, -0.1, 0.0, C["screen_bg"])
    X, Y, Z = s.coords()
    u = (X + hw) / width
    v = (Y - y0) / height
    inside = (X > -hw) & (X < hw) & (Y > y0) & (Y < y0 + height) & (Z > -0.1) & (Z < 0.0)
    # continents: blobby hash
    land = inside & ((np.sin(u * 13.0 + 1.3) * np.sin(v * 7.0 + 0.4) + 0.4 * np.sin(u * 31 + v * 9)) > 0.45)
    s.mask(land, C["screen_land"])
    # sine trajectory
    traj = inside & (np.abs(v - (0.5 + 0.32 * np.sin(u * math.tau * 1.5 + variant))) < 0.045)
    s.mask(traj, C["orange_glow"] if era != 5 else C["violet_glow"])
    grid = inside & ((np.floor(X * 10 + 1e-6) % 10 == 0) | (np.floor((Y - y0) * 10 + 1e-6) % 6 == 0)) & ~land & ~traj
    s.mask(grid, C["screen_map"])
    # the craft
    cx = -hw + width * 0.62
    cy = y0 + height * (0.5 + 0.32 * math.sin(0.62 * math.tau * 1.5 + variant))
    s.box(round(cx, 1) - 0.1, round(cx, 1) + 0.2, round(cy, 1) - 0.1, round(cy, 1) + 0.2, -0.1, 0.05, C["white_glow"])
    return s


@lru_cache(None)
def clock_row(era, n=3):
    """mission clocks: glowing digit bars (no text)"""
    s = Stamp(n * 1.0 + 0.2, 0.6, 0.2)
    for i in range(n):
        x = -n * 0.5 + i * 1.0 + 0.1
        s.box(x, x + 0.8, 0.0, 0.4, -0.1, 0.0, C["ink"])
        for j in range(4):
            s.box(x + 0.1 + j * 0.17, x + 0.2 + j * 0.17, 0.1, 0.3, 0.0, 0.05,
                  (C["red_glow"], C["amber_glow"], C["teal_glow"])[i % 3])
    return s


@lru_cache(None)
def gas_cage(era):
    s = Stamp(1.6, 2.0, 1.0)
    s.box(-0.7, 0.7, 0.0, 0.1, -0.4, 0.4, C["concrete"])
    cols = [C["leaf2"], C["grey"], C["blue"], C["orange"], C["leaf2"]]
    for i, x in enumerate(np.arange(-0.55, 0.6, 0.27)):
        s.cyl_y(round(x, 1), 0.0, 0.12, 0.1, 1.4, cols[i % len(cols)])
        s.box(round(x, 1) - 0.05, round(x, 1) + 0.05, 1.4, 1.55, -0.05, 0.05, C["grey_dk"])
    for x in (-0.75, 0.65):
        s.box(x, x + 0.1, 0.0, 1.8, -0.45, 0.45, C["grey_dk"])
    s.box(-0.75, 0.75, 1.7, 1.8, -0.45, 0.45, C["grey_dk"])
    for y in (0.6, 1.2):
        s.box(-0.75, 0.75, y, y + 0.05, 0.4, 0.45, C["hazard"])
    return s


@lru_cache(None)
def ac_unit(era):
    st = STYLES[era]
    s = Stamp(1.2, 1.0, 1.0)
    s.box(-0.5, 0.5, 0.0, 0.8, -0.4, 0.4, C["grey_lt"] if era != 4 else st["metal_dk"])
    s.cyl_z(0.0, 0.4, 0.3, 0.4, 0.45, C["grey_dk"])
    s.box(-0.05, 0.05, 0.1, 0.7, 0.4, 0.5, C["grey"])
    s.box(-0.3, 0.3, 0.35, 0.45, 0.4, 0.5, C["grey"])
    s.box(-0.5, 0.5, 0.8, 0.9, -0.4, 0.4, C["grey"])
    return s


@lru_cache(None)
def solar_panel(era, w=2.0, d=1.2):
    """a tilted panel in three steps, cells in 0.5 m blocks"""
    s = Stamp(w + 0.2, 1.4, d + 0.4)
    hd = d / 2
    cells = (P("#22407a"), P("#2c4f91"))
    for k in range(3):
        z0 = -hd + k * d / 3
        y = 0.6 - k * 0.1
        for i, x in enumerate(np.arange(-w / 2, w / 2 - 0.01, 0.5)):
            s.box(x, min(x + 0.5, w / 2), y, y + 0.1, z0, z0 + d / 3, cells[(i + k) % 2])
    s.box(-w / 2, w / 2, 0.7, 0.8, -hd, -hd + 0.1, P("#5f7fb8"))
    s.box(-w / 2 + 0.2, -w / 2 + 0.3, 0.0, 0.5, -0.1, 0.0, C["grey_dk"])
    s.box(w / 2 - 0.3, w / 2 - 0.2, 0.0, 0.5, -0.1, 0.0, C["grey_dk"])
    s.box(-w / 2 + 0.2, -w / 2 + 0.3, 0.0, 0.9, hd - 0.1, hd, C["grey_dk"])
    s.box(w / 2 - 0.3, w / 2 - 0.2, 0.0, 0.9, hd - 0.1, hd, C["grey_dk"])
    return s


@lru_cache(None)
def water_tank(era):
    s = Stamp(2.0, 3.4, 2.0)
    wood = era <= 2
    for (x, z) in ((-0.7, -0.7), (0.6, -0.7), (-0.7, 0.6), (0.6, 0.6)):
        s.box(x, x + 0.1, 0.0, 1.6, z, z + 0.1, C["crate_dk"] if wood else C["grey_dk"])
    s.box(-0.7, 0.7, 0.8, 0.9, -0.7, -0.6, C["crate_dk"] if wood else C["grey_dk"])
    s.cyl_y(0, 0, 0.8, 1.6, 2.9, C["crate"] if wood else C["grey_lt"])
    for y in (1.8, 2.4):
        s.cyl_y(0, 0, 0.84, y, y + 0.1, C["grey_dk"])
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    s.mask((Y > 2.9) & (Y < 3.3) & (R < 0.9 - (Y - 2.9) * 2.0), C["roof_cone"] if "roof_cone" in C else C["pot2"])
    return s


@lru_cache(None)
def vent(era):
    s = Stamp(0.6, 1.0, 0.6)
    s.cyl_y(0, 0, 0.2, 0.0, 0.6, C["grey"])
    s.cyl_y(0, 0, 0.3, 0.6, 0.7, C["grey_dk"])
    s.cyl_y(0, 0, 0.22, 0.7, 0.8, C["grey"])
    return s


@lru_cache(None)
def skylight(era, w=2.0, d=1.2):
    st = STYLES[era]
    s = Stamp(w + 0.2, 0.6, d + 0.2)
    s.box(-w / 2, w / 2, 0.0, 0.3, -d / 2, d / 2, st["metal_dk"])
    s.box(-w / 2 + 0.1, w / 2 - 0.1, 0.3, 0.4, -d / 2 + 0.1, d / 2 - 0.1, st["glass_dim"])
    return s


@lru_cache(None)
def hatch(era):
    st = STYLES[era]
    s = Stamp(1.2, 0.8, 1.2)
    s.box(-0.5, 0.5, 0.0, 0.3, -0.5, 0.5, st["metal_dk"])
    s.box(-0.4, 0.4, 0.3, 0.4, -0.4, 0.4, st["accent"] if era in (3, 4) else C["grey"])
    s.box(-0.1, 0.1, 0.4, 0.5, 0.2, 0.3, C["grey_dk"])
    return s


@lru_cache(None)
def dome(era, r=2.0, slit=False):
    st = STYLES[era]
    s = Stamp(2 * r + 0.4, r + 0.6, 2 * r + 0.4)
    s.sphere(0, 0.0, 0, r, C["white"] if era != 5 else st["glass_dim"], rin=r - 0.25, ymin=0.0)
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Y ** 2 + Z ** 2)
    if era == 5:
        s.mask((R <= r + 0.06) & (R > r - 0.3) & (Y >= 0) & (Y < r * 0.35), st["roof_cap"])
        s.mask((R <= r + 0.06) & (R > r - 0.3) & (np.abs(Y - r * 0.68) < 0.06), st["roof_cap"])
    ribs = (R <= r + 0.06) & (R > r - 0.1) & (np.abs(np.arctan2(Z, X) % (math.pi / 4)) < 0.07) & (Y > 0)
    s.mask(ribs, st["roof"][0] if era != 5 else st["roof_cap"])
    s.mask((R <= r + 0.08) & (R > r - 0.2) & (Y < 0.2), st["trim"] if era == 5 else st["roof"][0])
    if slit:
        s.mask((np.abs(X) < 0.35) & (Z > -0.2) & (Y > 0.3), 0)
    else:
        s.sphere(0, r - 0.05, 0, 0.25, st["trim"] if era >= 4 else C["red_glow"], ymin=r - 0.1)
    return s


@lru_cache(None)
def greenhouse(era, w=3.0, d=2.4, h=2.2):
    st = STYLES[era]
    s = Stamp(w + 0.2, h + 1.4, d + 0.2)
    hw, hd = w / 2, d / 2
    glass = P("#bff0d0", 0.9)
    s.box(-hw, hw, 0.0, 0.3, -hd, hd, st["metal_dk"])
    # glass walls and a stepped glass roof
    s.box(-hw, hw, 0.3, h, -hd, -hd + 0.1, glass)
    s.box(-hw, hw, 0.3, h, hd - 0.1, hd, glass)
    s.box(-hw, -hw + 0.1, 0.3, h, -hd, hd, glass)
    s.box(hw - 0.1, hw, 0.3, h, -hd, hd, glass)
    for k in range(int(hd * 10)):
        z = -hd + k * 0.1
        y = h + min(k, int(hd * 10) - k) * 0.05
        s.box(-hw, hw, round(y, 1), round(y, 1) + 0.1, z, z + 0.1, glass)
    for x in np.arange(-hw, hw + 0.01, 0.6):
        s.box(x, x + 0.1, 0.3, h + 0.6, -hd, -hd + 0.1, st["frame"])
        s.box(x, x + 0.1, 0.3, h + 0.6, hd - 0.1, hd, st["frame"])
    # plants inside (rows of green with violet grow lights)
    for i, x in enumerate(np.arange(-hw + 0.3, hw - 0.3, 0.5)):
        s.box(x, x + 0.3, 0.3, 0.5, -hd + 0.3, hd - 0.3, C["soil"])
        s.box(x, x + 0.3, 0.5, 0.8 + 0.1 * (i % 3), -hd + 0.4, hd - 0.4, (C["leaf3"], C["leaf"], C["green_glow"])[i % 3])
    s.box(-hw + 0.2, hw - 0.2, h - 0.2, h - 0.1, -0.1, 0.1, C["violet_glow"])
    return s


@lru_cache(None)
def dish(era, r=2.0, tilt=0.6, mast=2.0):
    """parabolic dish on a mast, opening up and towards +z by `tilt` radians"""
    st = STYLES[era]
    size = 2 * r + 0.6
    s = Stamp(size, mast + 2 * r + 0.6, size)
    s.box(-0.3, 0.3, 0.0, 0.4, -0.3, 0.3, C["concrete"])
    s.box(-0.15, 0.15, 0.4, mast, -0.15, 0.15, st["metal_dk"])
    s.box(-0.3, 0.3, mast - 0.2, mast + 0.2, -0.3, 0.3, st["metal_dk"])
    X, Y, Z = s.coords()
    c = np.array([0.0, mast + 0.4, 0.0])
    ax = np.array([0.0, math.cos(tilt), math.sin(tilt)])
    ry, rz = Y - c[1], Z - c[2]
    t = ry * ax[1] + rz * ax[2]
    py, pz = ry - t * ax[1], rz - t * ax[2]
    rr2 = X ** 2 + py ** 2 + pz ** 2
    f = r * 0.9
    shell = (np.sqrt(rr2) < r) & (np.abs(t - rr2 / (4 * f)) < 0.09)
    s.mask(shell, C["white"] if era != 4 else C["grey_lt"])
    rim = (np.sqrt(rr2) < r) & (np.sqrt(rr2) > r - 0.12) & (np.abs(t - rr2 / (4 * f)) < 0.12)
    s.mask(rim, st["accent"] if era != 1 else C["grey"])
    # feed horn on struts
    fp = c + ax * f * 0.8
    for k in range(int(f * 0.8 * 10)):
        p = c + ax * (k * 0.1)
        s.box(p[0] - 0.05, p[0] + 0.05, p[1] - 0.05, p[1] + 0.05, p[2] - 0.05, p[2] + 0.05, st["metal_dk"])
    s.box(fp[0] - 0.15, fp[0] + 0.15, fp[1] - 0.15, fp[1] + 0.15, fp[2] - 0.15, fp[2] + 0.15,
          C["red_glow"] if era < 4 else (st["led"]))
    return s


@lru_cache(None)
def lamp_post(era):
    st = STYLES[era]
    s = Stamp(1.0, 3.6, 1.0)
    s.box(-0.15, 0.15, 0.0, 0.2, -0.15, 0.15, st["metal_dk"])
    s.box(-0.05, 0.05, 0.2, 3.2, -0.05, 0.05, st["metal_dk"])
    s.box(-0.05, 0.05, 3.1, 3.2, -0.05, 0.4, st["metal_dk"])
    s.box(-0.15, 0.15, 2.9, 3.1, 0.2, 0.45, st["lamp"])
    return s


@lru_cache(None)
def banner(era, h=4.0):
    """pole with a hanging banner showing the agency star (faces +z)"""
    st = STYLES[era]
    s = Stamp(1.4, h + 0.4, 0.6)
    s.box(-0.65, -0.55, 0.0, h + 0.2, -0.05, 0.05, st["metal_dk"])
    s.box(-0.65, 0.55, h - 0.1, h, -0.05, 0.05, st["metal_dk"])
    s.box(-0.5, 0.5, h - 2.0, h - 0.1, -0.05, 0.05, st["banner"])
    s.box(-0.5, -0.4, h - 2.2, h - 2.0, -0.05, 0.05, st["banner"])
    s.box(0.4, 0.5, h - 2.2, h - 2.0, -0.05, 0.05, st["banner"])
    _sparkle(s, 0.0, h - 0.9, 0.05, 0.1, C["white"] if era != 2 else C["yellow"], sc=0.1)
    s.box(-0.5, 0.5, h - 1.85, h - 1.75, 0.05, 0.1, C["orange"] if era != 3 else C["white"])
    s.box(-0.7, -0.5, 0.0, 0.1, -0.1, 0.1, C["concrete"])
    return s


@lru_cache(None)
def bike(era, variant=0):
    s = Stamp(1.6, 1.0, 0.4)
    c = (C["red"], C["blue_lt"], C["leaf3"], C["orange"])[variant % 4]
    for x in (-0.5, 0.5):
        s.cyl_z(x, 0.3, 0.3, -0.05, 0.05, C["rubber"], rin=0.2)
    s.box(-0.5, 0.4, 0.4, 0.5, -0.05, 0.05, c)
    s.box(-0.1, 0.0, 0.3, 0.8, -0.05, 0.05, c)
    s.box(0.35, 0.45, 0.4, 0.9, -0.05, 0.05, c)
    s.box(-0.2, 0.1, 0.8, 0.9, -0.1, 0.1, C["ink"])
    s.box(0.3, 0.5, 0.9, 1.0, -0.2, 0.2, C["grey_dk"])
    s.box(0.5, 0.7, 0.6, 0.8, -0.1, 0.1, C["crate"])
    return s


@lru_cache(None)
def bench(era):
    st = STYLES[era]
    s = Stamp(2.0, 1.0, 0.8)
    wood = C["crate"] if era <= 3 else st["metal"]
    for z in (-0.2, 0.0, 0.2):
        s.box(-0.9, 0.9, 0.4, 0.5, z - 0.05, z + 0.05, wood)
    s.box(-0.9, 0.9, 0.6, 0.7, -0.3, -0.2, wood)
    s.box(-0.9, 0.9, 0.8, 0.9, -0.3, -0.2, wood)
    for x in (-0.8, 0.7):
        s.box(x, x + 0.1, 0.0, 0.9, -0.3, -0.2, st["metal_dk"])
        s.box(x, x + 0.1, 0.0, 0.4, 0.1, 0.2, st["metal_dk"])
    return s


@lru_cache(None)
def planter(era, w=2.0, d=0.8, variant=0):
    st = STYLES[era]
    s = Stamp(w + 0.2, 1.4, d + 0.2)
    box_c = {1: C["crate"], 2: C["concrete"], 3: C["white"], 4: st["metal_dk"], 5: st["wall"][0]}[era]
    s.box(-w / 2, w / 2, 0.0, 0.5, -d / 2, d / 2, box_c)
    s.box(-w / 2 + 0.1, w / 2 - 0.1, 0.4, 0.5, -d / 2 + 0.1, d / 2 - 0.1, C["soil"])
    for i, x in enumerate(np.arange(-w / 2 + 0.2, w / 2 - 0.1, 0.3)):
        hh = 0.2 + 0.1 * ((i * 3 + variant) % 4)
        s.box(x, x + 0.2, 0.5, 0.5 + hh, -d / 2 + 0.2, d / 2 - 0.2, (C["leaf"], C["leaf3"], C["leaf2"])[(i + variant) % 3])
        if (i + variant) % 3 == 0:
            s.box(x, x + 0.1, 0.5 + hh, 0.6 + hh, -0.05, 0.05, (C["flower_r"], C["flower_y"], C["flower_p"])[i % 3])
    if era == 4:
        s.box(-w / 2, w / 2, 0.0, 0.1, d / 2, d / 2 + 0.1, st["led"])
    return s


@lru_cache(None)
def nose_cone(era):
    s = Stamp(1.6, 2.0, 1.6)
    s.box(-0.7, 0.7, 0.0, 0.2, -0.7, 0.7, C["crate"])
    X, Y, Z = s.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    yy = (Y - 0.2) / 1.6
    m = (Y > 0.2) & (R < 0.6 * np.sqrt(np.clip(1 - yy, 0, 1)) + 0.02)
    s.mask(m, C["rocket"])
    s.mask(m & (Y > 0.4) & (Y < 0.5), C["orange"])
    return s


@lru_cache(None)
def cone(era):
    s = Stamp(0.4, 0.6, 0.4)
    s.box(-0.2, 0.2, 0.0, 0.1, -0.2, 0.2, C["cone"])
    s.box(-0.1, 0.1, 0.1, 0.5, -0.1, 0.1, C["cone"])
    s.box(-0.1, 0.1, 0.3, 0.4, -0.1, 0.1, C["white"])
    return s


@lru_cache(None)
def fence(era, length=4.0):
    st = STYLES[era]
    s = Stamp(length, 1.2, 0.2)
    hl = length / 2
    if era == 1:
        for x in np.arange(-hl, hl, 0.6):
            s.box(x, x + 0.1, 0.0, 1.0, -0.05, 0.05, C["crate"])
        for y in (0.3, 0.7):
            s.box(-hl, hl, y, y + 0.1, -0.05, 0.05, C["crate2"])
    else:
        for x in np.arange(-hl, hl, 1.0):
            s.box(x, x + 0.1, 0.0, 1.1, -0.05, 0.05, st["metal_dk"])
        s.box(-hl, hl, 1.0, 1.1, -0.05, 0.05, st["metal_dk"])
        X, Y, Z = s.coords()
        mesh = ((np.floor(X * 10 + 1e-6) + np.floor(Y * 10 + 1e-6)) % 3 == 0) & (Y > 0.1) & (Y < 1.0) & (np.abs(Z) < 0.05)
        s.mask(mesh, st["metal"])
    return s


@lru_cache(None)
def cart(era):
    s = Stamp(1.6, 1.0, 1.0)
    s.box(-0.6, 0.6, 0.3, 0.7, -0.4, 0.4, C["crate"] if era <= 2 else C["grey"])
    s.box(-0.5, 0.5, 0.7, 0.9, -0.3, 0.3, C["paper"])
    s.box(0.6, 0.8, 0.6, 0.7, -0.05, 0.05, C["grey_dk"])
    for x in (-0.4, 0.3):
        s.cyl_z(x + 0.05, 0.2, 0.2, -0.45, -0.35, C["rubber"])
        s.cyl_z(x + 0.05, 0.2, 0.2, 0.35, 0.45, C["rubber"])
    return s


@lru_cache(None)
def mailbox(era):
    s = Stamp(0.6, 1.4, 0.6)
    s.box(-0.05, 0.05, 0.0, 1.0, -0.05, 0.05, C["grey_dk"])
    s.box(-0.2, 0.2, 1.0, 1.3, -0.25, 0.25, C["blue"] if era != 3 else C["orange"])
    s.box(0.2, 0.25, 1.15, 1.35, 0.0, 0.05, C["red"])
    return s


@lru_cache(None)
def bulb_string(length):
    s = Stamp(length, 0.4, 0.2)
    hl = length / 2
    for i, x in enumerate(np.arange(-hl, hl, 0.1)):
        sag = 0.1 * (1 - (2 * x / length) ** 2)
        y = round(0.3 - sag, 1)
        s.box(x, x + 0.1, y, y + 0.05, -0.05, 0.05, C["ink"])
        if i % 4 == 2:
            s.box(x, x + 0.1, y - 0.1, y, -0.05, 0.05, C["warm_glow"])
    return s
