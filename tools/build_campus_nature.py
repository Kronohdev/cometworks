"""Small voxel props that dress the Cometworks campus (scenes/tycoon/campus.tscn), in the same
10 cm voxel style and baked-AO meshing as the buildings (tools/campus_voxel.py):

  assets/campus/nature/   trees (round, pine, blossom), bushes, rocks, grass tufts, flower
                          clumps, reeds: scattered by MultiMeshInstance3D nodes (the meshes are
                          extracted to .res by tools/extract_campus_meshes.gd)
  assets/campus/dressing/ fences (wood / steel), a windsock, hay bales, a bench, the plaza
                          monument, planters, a floodlight mast, a beacon mast, picnic table,
                          a fuel cart: placed by hand under Dressing in the campus scene, shown per
                          era through metadata (era_min / era_max)

Do not touch the building models (tools/build_campus_buildings.py): they are large.

Usage: python tools/build_campus_nature.py
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import campus_voxel as cv  # noqa: E402
from campus_voxel import Grid, Stamp, PAL  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MAT = "res://assets/campus/campus_voxel.tres"
FOLIAGE_MAT = "res://assets/campus/nature/foliage.tres"

# palette (sRGB hex; PAL converts to linear and keeps glow)
LEAF = ["#3f7a4f", "#4f8f58", "#5ea862", "#356b48", "#2c5a40"]
PINE = ["#2f5e4a", "#264f40", "#3a6d55"]
BLOSSOM = ["#f2a7c3", "#f7c6d8", "#e58fb0"]
TRUNK = ["#6b4f3a", "#5a4130", "#7a5a40"]
GRASS = ["#4f8f58", "#5ea862", "#6db86a", "#3f7a4f"]
FLOWER = {"yellow": "#ffd35a", "pink": "#ff8fb8", "white": "#f4f1ea", "violet": "#a68cff", "orange": "#ff9a52",
          "ice": "#bfe8ff"}
ROCK = ["#6f7782", "#5d646f", "#848b94", "#525963"]
WOOD = ["#8a6544", "#76563a", "#9b7450"]
STEEL = ["#7b8798", "#5d687a", "#9aa5b4"]
CONCRETE = ["#9aa1ab", "#8a919b"]
HAY = ["#d9b85c", "#c7a64f", "#e6c76d"]


def rng(seed):
    return np.random.default_rng(seed)


def cell_rand(shape, r, cell=3):
    """random field in [0, 1) that is constant over cell^3 voxel blocks (keeps the greedy
    mesher's quads large: per-voxel colour noise would multiply the triangle count; the
    campus shader adds its own per-voxel jitter anyway)"""
    n = [s // cell + 2 for s in shape]
    f = r.random(n)
    f = np.repeat(np.repeat(np.repeat(f, cell, 0), cell, 1), cell, 2)
    o = r.integers(0, cell, 3)
    return f[o[0]:o[0] + shape[0], o[1]:o[1] + shape[1], o[2]:o[2] + shape[2]]


def speckle(st, mask, colors, r, weights=None, cell=3):
    """paint the voxels of mask with colours picked at random per block of cell^3 voxels"""
    mask = np.broadcast_to(mask, st.col.shape)
    if not mask.any():
        return
    pal = np.array([PAL(c) for c in colors], np.uint8)
    w = np.cumsum(weights if weights is not None else [1.0 / len(colors)] * len(colors))
    w = w / w[-1]
    f = cell_rand(st.col.shape, r, cell)
    pick = np.searchsorted(w, f, side="right").clip(0, len(pal) - 1)
    st.col[mask] = pal[pick[mask]]


def blob(st, centers, r, colors, top_light=None, weights=None):
    """union of spheres (cx, cy, cz, radius) with a lumpy, blocky surface"""
    X, Y, Z = st.coords()
    m = np.zeros(st.col.shape, bool)
    jit = cell_rand(st.col.shape, r, 2) * 0.22
    for (cx, cy, cz, rad) in centers:
        d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2 + (Z - cz) ** 2)
        m |= d + jit < rad
    speckle(st, m, colors, r, weights, cell=4)
    if top_light:
        # lighter blocks on top: the canopy catches the sky
        top = m & ~np.roll(m, -1, axis=1)
        sel = top & (cell_rand(st.col.shape, r, 4) < 0.45)
        speckle(st, sel, [top_light], r)
    return m


# ------------------------------------------------------------------ nature
def tree_round(v):
    r = rng(100 + v)
    h = [2.0, 2.4, 1.7][v % 3]
    st = Stamp(4.4, 5.6, 4.4)
    st.box(-0.2, 0.2, 0.0, h + 0.6, -0.2, 0.2, PAL(TRUNK[v % 3]))
    st.box(-0.3, 0.3, 0.0, 0.2, -0.3, 0.3, PAL(TRUNK[1]))  # root flare
    st.box(0.1, 0.6, h - 0.4, h - 0.25, -0.08, 0.08, PAL(TRUNK[0]))  # a branch
    rad = [1.45, 1.6, 1.25][v % 3]
    cs = [(0, h + 1.1, 0, rad), (0.6, h + 0.7, 0.3, rad * 0.75), (-0.5, h + 0.8, -0.4, rad * 0.7),
          (0.1, h + 1.8, -0.1, rad * 0.65)]
    leaves = [LEAF[(v + k) % len(LEAF)] for k in range(3)]
    blob(st, cs, r, leaves, top_light="#7cc46e", weights=[0.5, 0.3, 0.2])
    return st


def tree_pine(v):
    r = rng(200 + v)
    st = Stamp(3.4, 6.8, 3.4)
    st.box(-0.15, 0.15, 0.0, 1.4, -0.15, 0.15, PAL(TRUNK[1]))
    X, Y, Z = st.coords()
    R = np.sqrt(X ** 2 + Z ** 2)
    tiers = [(1.0, 2.6, 1.55), (2.2, 3.9, 1.25), (3.4, 5.1, 0.95), (4.6, 6.3, 0.6)]
    m = np.zeros(st.col.shape, bool)
    for (y0, y1, rad) in tiers[: 4 if v % 2 == 0 else 3]:
        t = np.clip((Y - y0) / (y1 - y0), 0, 1)
        m |= (Y >= y0) & (Y <= y1) & (R + cell_rand(st.col.shape, r, 2) * 0.12 < rad * (1 - t * 0.85))
    speckle(st, m, PINE, r, [0.5, 0.3, 0.2], cell=4)
    top = m & ~np.roll(m, -1, axis=1) & (cell_rand(st.col.shape, r, 3) < 0.35)
    speckle(st, top, ["#5d8f6e"], r)
    return st


def tree_blossom(v):
    r = rng(300 + v)
    st = Stamp(4.0, 4.8, 4.0)
    h = 1.6
    st.box(-0.18, 0.18, 0.0, h + 0.5, -0.18, 0.18, PAL(TRUNK[0]))
    st.box(-0.6, -0.1, h, h + 0.12, -0.06, 0.06, PAL(TRUNK[0]))
    st.box(0.1, 0.5, h + 0.2, h + 0.32, -0.06, 0.06, PAL(TRUNK[2]))
    cs = [(0, h + 1.0, 0, 1.25), (-0.7, h + 0.7, 0.2, 0.8), (0.6, h + 0.85, -0.3, 0.85)]
    blob(st, cs, r, BLOSSOM + [LEAF[2]], top_light="#ffe0ec", weights=[0.4, 0.3, 0.2, 0.1])
    return st


def bush(v):
    r = rng(400 + v)
    st = Stamp(2.0, 1.3, 2.0)
    cs = [(0, 0.45, 0, 0.6 + 0.1 * (v % 2)), (0.4, 0.35, 0.2, 0.45), (-0.35, 0.35, -0.2, 0.45)]
    m = blob(st, cs, r, [LEAF[(v + 1) % 5], LEAF[(v + 3) % 5], LEAF[0]], top_light="#7cc46e", weights=[0.5, 0.3, 0.2])
    if v >= 2:  # flowering bush
        top = m & ~np.roll(m, -1, axis=1) & (cell_rand(st.col.shape, r, 2) < 0.3)
        speckle(st, top, [FLOWER[["pink", "yellow", "white", "violet"][v % 4]]], r)
    return st


def rock(v):
    r = rng(500 + v)
    size = [0.9, 1.5, 0.6, 2.2][v % 4]
    st = Stamp(size * 2 + 0.4, size * 1.4 + 0.3, size * 2 + 0.4)
    cs = [(0, size * 0.25, 0, size * 0.8), (size * 0.4, size * 0.2, size * 0.2, size * 0.55),
          (-size * 0.35, size * 0.15, -size * 0.25, size * 0.5)]
    X, Y, Z = st.coords()
    m = np.zeros(st.col.shape, bool)
    for (cx, cy, cz, rad) in cs:
        d = np.sqrt(((X - cx) / 1.0) ** 2 + ((Y - cy) / 0.75) ** 2 + ((Z - cz) / 1.0) ** 2)
        m |= d + cell_rand(st.col.shape, r, 2) * 0.14 < rad
    m &= Y < size * 1.2
    speckle(st, m, ROCK, r, [0.35, 0.3, 0.2, 0.15], cell=4)
    moss = m & ~np.roll(m, -1, axis=1) & (cell_rand(st.col.shape, r, 3) < 0.3)
    speckle(st, moss, ["#4f8f58", "#3f7a4f"], r)
    return st


def grass_tuft(v):
    r = rng(600 + v)
    st = Stamp(0.8, 0.7, 0.8)
    for k in range(9 + v * 3):
        x, z = r.uniform(-0.3, 0.3, 2)
        h = r.uniform(0.2, 0.55)
        st.box(x - 0.05, x + 0.05, 0.0, h, z - 0.05, z + 0.05, PAL(GRASS[k % 4]))
    return st


def flowers(v):
    r = rng(700 + v)
    st = Stamp(1.0, 0.7, 1.0)
    col = ["yellow", "pink", "white", "violet", "orange", "ice"][v % 6]
    for k in range(7):
        x, z = r.uniform(-0.35, 0.35, 2)
        h = r.uniform(0.15, 0.4)
        st.box(x - 0.05, x + 0.05, 0.0, h, z - 0.05, z + 0.05, PAL(GRASS[k % 4]))
    for k in range(5):
        x, z = r.uniform(-0.3, 0.3, 2)
        h = r.uniform(0.3, 0.5)
        st.box(x - 0.05, x + 0.05, 0.0, h, z - 0.05, z + 0.05, PAL(GRASS[1]))
        st.box(x - 0.1, x + 0.1, h, h + 0.1, z - 0.1, z + 0.1, PAL(FLOWER[col]))
        st.box(x - 0.05, x + 0.05, h + 0.1, h + 0.15, z - 0.05, z + 0.05, PAL("#ffe08a" if col != "yellow" else "#ff9a52"))
    return st


def reeds(v):
    r = rng(800 + v)
    st = Stamp(1.0, 1.5, 1.0)
    for k in range(10):
        x, z = r.uniform(-0.35, 0.35, 2)
        h = r.uniform(0.6, 1.3)
        st.box(x - 0.05, x + 0.05, 0.0, h, z - 0.05, z + 0.05, PAL(["#7d9a5a", "#6b8a4f", "#93a866"][k % 3]))
        if k % 3 == 0:
            st.box(x - 0.05, x + 0.05, h, h + 0.2, z - 0.05, z + 0.05, PAL("#6b4f3a"))
    return st


# ------------------------------------------------------------------ dressing
def fence_wood(v):
    """4 m along x, posts every metre, two rails (era 1-2)"""
    st = Stamp(4.2, 1.2, 0.4)
    for k in range(5):
        x = -2.0 + k * 1.0
        st.box(x - 0.06, x + 0.06, 0.0, 1.0 + (0.1 if k % 2 == 0 else 0.0), -0.06, 0.06, PAL(WOOD[1]))
    st.box(-2.0, 2.0, 0.35, 0.47, -0.04, 0.04, PAL(WOOD[0]))
    st.box(-2.0, 2.0, 0.72, 0.84, -0.04, 0.04, PAL(WOOD[2]))
    return st


def fence_steel(v):
    """4 m security fence: steel posts and a mesh panel (era 3-5)"""
    st = Stamp(4.2, 2.2, 0.4)
    for x in (-2.0, 0.0, 2.0):
        st.box(x - 0.06, x + 0.06, 0.0, 2.0, -0.06, 0.06, PAL(STEEL[1]))
    st.box(-2.0, 2.0, 1.9, 2.0, -0.04, 0.04, PAL(STEEL[0]))
    st.box(-2.0, 2.0, 0.1, 0.2, -0.04, 0.04, PAL(STEEL[0]))
    st.box(-2.0, 2.0, 1.0, 1.08, -0.04, 0.04, PAL(STEEL[0]))
    for k in range(20):
        x = -1.9 + k * 0.2
        st.box(x - 0.05, x + 0.05, 0.2, 1.9, -0.05, 0.05, PAL(STEEL[2]))
    return st


def windsock(v):
    st = Stamp(2.4, 4.6, 1.0)
    st.box(-0.06, 0.06, 0.0, 4.0, -0.06, 0.06, PAL(STEEL[0]))
    st.box(-0.15, 0.15, 0.0, 0.2, -0.15, 0.15, PAL(CONCRETE[0]))
    X, Y, Z = st.coords()
    for k in range(5):
        x0 = 0.1 + k * 0.38
        rad = 0.32 - k * 0.04
        sag = k * 0.06
        m = (X >= x0) & (X < x0 + 0.38) & (np.sqrt((Y - (3.75 - sag)) ** 2 + Z ** 2) < rad)
        st.mask(m, PAL("#ff8a3d" if k % 2 == 0 else "#f4f1ea"))
    return st


def hay_bale(v):
    r = rng(900 + v)
    st = Stamp(1.6, 1.3, 1.6)
    st.cyl_z(0, 0.6, 0.6, -0.6, 0.6, PAL(HAY[0]))
    X, Y, Z = st.coords()
    m = (np.sqrt(X ** 2 + (Y - 0.6) ** 2) < 0.6) & (np.abs(Z) <= 0.6)
    speckle(st, m, HAY, r, [0.5, 0.3, 0.2], cell=4)
    st.cyl_z(0, 0.6, 0.62, -0.25, -0.15, PAL("#8a6544"))
    st.cyl_z(0, 0.6, 0.62, 0.15, 0.25, PAL("#8a6544"))
    return st


def bench(v):
    st = Stamp(2.4, 1.0, 0.9)
    wood = PAL(WOOD[v % 3])
    leg = PAL(STEEL[1] if v % 2 else WOOD[1])
    for x in (-1.0, 1.0):
        st.box(x - 0.08, x + 0.08, 0.0, 0.45, -0.25, 0.25, leg)
        st.box(x - 0.08, x + 0.08, 0.45, 0.9, -0.3, -0.2, leg)
    for k in range(3):
        z = -0.2 + k * 0.17
        st.box(-1.15, 1.15, 0.42, 0.5, z - 0.07, z + 0.07, wood)
    st.box(-1.15, 1.15, 0.62, 0.72, -0.32, -0.22, wood)
    st.box(-1.15, 1.15, 0.8, 0.88, -0.32, -0.22, wood)
    return st


def monument(v):
    """the plaza monument: a stone plinth with the Cometlings' four-pointed star"""
    st = Stamp(2.0, 3.4, 2.0)
    st.box(-0.8, 0.8, 0.0, 0.2, -0.8, 0.8, PAL(CONCRETE[1]))
    st.box(-0.6, 0.6, 0.2, 1.1, -0.6, 0.6, PAL(CONCRETE[0]))
    st.box(-0.7, 0.7, 1.0, 1.15, -0.7, 0.7, PAL(CONCRETE[1]))
    st.box(-0.35, 0.35, 0.45, 0.75, 0.6, 0.65, PAL("#b98a3e"))  # bronze plaque
    X, Y, Z = st.coords()
    cy = 2.15
    ax, ay = np.abs(X), np.abs(Y - cy)
    star = (ax * ay * 7.0 + (ax + ay) * 0.5 < 0.5) & (np.abs(Z) < 0.12)
    st.mask(star, PAL("#e9eef7"))
    core = (np.sqrt(X ** 2 + (Y - cy) ** 2) < 0.16) & (np.abs(Z) < 0.16)
    st.mask(core, PAL("#3fe0c5", glow=4.0))
    st.box(-0.05, 0.05, 1.15, 1.5, -0.05, 0.05, PAL(STEEL[1]))
    return st


def planter(v):
    r = rng(1000 + v)
    st = Stamp(2.4, 1.0, 1.0)
    box = PAL([WOOD[0], CONCRETE[0], "#3a4d72"][v % 3])
    st.box(-1.1, 1.1, 0.0, 0.45, -0.4, 0.4, box)
    st.box(-1.0, 1.0, 0.35, 0.45, -0.3, 0.3, PAL("#5a4130"))
    for k in range(10):
        x, z = r.uniform(-0.9, 0.9), r.uniform(-0.22, 0.22)
        h = r.uniform(0.55, 0.8)
        st.box(x - 0.05, x + 0.05, 0.45, h, z - 0.05, z + 0.05, PAL(GRASS[k % 4]))
        col = list(FLOWER.values())[(k + v) % 5]
        st.box(x - 0.1, x + 0.1, h, h + 0.1, z - 0.1, z + 0.1, PAL(col))
    return st


def floodlight(v):
    """lattice mast with a bank of lamps (launch-base era)"""
    st = Stamp(1.6, 12.0, 1.6)
    s = PAL(STEEL[0])
    for (x, z) in ((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)):
        st.box(x - 0.05, x + 0.05, 0.0, 10.6, z - 0.05, z + 0.05, s)
    for k in range(21):
        y = k * 0.5
        if k % 2 == 0:
            st.box(-0.35, 0.35, y, y + 0.08, -0.35, -0.27, s)
            st.box(-0.35, 0.35, y, y + 0.08, 0.27, 0.35, s)
        else:
            st.box(-0.35, -0.27, y, y + 0.08, -0.35, 0.35, s)
            st.box(0.27, 0.35, y, y + 0.08, -0.35, 0.35, s)
    st.box(-0.7, 0.7, 10.6, 10.8, -0.5, 0.5, PAL(STEEL[1]))
    st.box(-0.7, 0.7, 10.8, 11.6, -0.25, 0.25, PAL(STEEL[1]))
    for x in (-0.5, -0.17, 0.17, 0.5):
        st.box(x - 0.13, x + 0.13, 10.9, 11.5, 0.25, 0.32, PAL("#fff1d6", glow=6.0))
    st.box(-0.08, 0.08, 11.6, 11.85, -0.08, 0.08, PAL("#ff5c6c", glow=5.0))
    return st


def beacon_mast(v):
    st = Stamp(1.0, 9.0, 1.0)
    for k in range(8):
        y = k * 1.0
        st.box(-0.1, 0.1, y, y + 1.0, -0.1, 0.1, PAL("#e9eef7" if k % 2 == 0 else "#ff5c6c"))
    st.box(-0.25, 0.25, 0.0, 0.2, -0.25, 0.25, PAL(CONCRETE[0]))
    st.box(-0.15, 0.15, 8.0, 8.3, -0.15, 0.15, PAL(STEEL[1]))
    return st


def picnic_table(v):
    st = Stamp(2.2, 1.0, 2.0)
    w = PAL(WOOD[v % 3])
    w2 = PAL(WOOD[(v + 1) % 3])
    st.box(-1.0, 1.0, 0.7, 0.8, -0.4, 0.4, w)
    for x in (-0.8, 0.8):
        st.box(x - 0.06, x + 0.06, 0.0, 0.7, -0.06, 0.06, w2)
        st.box(x - 0.06, x + 0.06, 0.4, 0.48, -0.85, 0.85, w2)
    st.box(-1.0, 1.0, 0.42, 0.5, -0.85, -0.6, w)
    st.box(-1.0, 1.0, 0.42, 0.5, 0.6, 0.85, w)
    return st


def crate_stack(v):
    r = rng(1100 + v)
    st = Stamp(2.4, 2.0, 1.6)
    cols = ["#8a6544", "#76563a", "#a07a52"]
    for (x, y, z, s) in ((-0.55, 0.0, 0.0, 0.9), (0.45, 0.0, 0.1, 0.8), (-0.4, 0.9, 0.05, 0.7)):
        c = PAL(cols[int(r.integers(0, 3))])
        h = s / 2
        st.box(x - h, x + h, y, y + s, z - h, z + h, c)
        st.box(x - h, x + h, y + s * 0.45, y + s * 0.55, z - h - 0.02, z + h + 0.02, PAL("#5a4130"))
    return st


def fuel_cart(v):
    st = Stamp(3.2, 2.0, 1.6)
    st.box(-1.4, 1.4, 0.3, 0.45, -0.6, 0.6, PAL(STEEL[1]))
    for x in (-1.0, 1.0):
        for z in (-0.6, 0.6):
            st.cyl_z(x, 0.25, 0.25, z - 0.1, z + 0.1, PAL("#1b2433"))
    st.cyl_x(1.05, 0.0, 0.55, -1.3, 1.1, PAL("#e9eef7"))
    st.cyl_x(1.05, 0.0, 0.57, -0.5, -0.35, PAL("#ff8a3d"))
    st.cyl_x(1.05, 0.0, 0.57, 0.35, 0.5, PAL("#ff8a3d"))
    st.box(1.1, 1.4, 0.45, 1.3, -0.35, 0.35, PAL("#3a4d72"))
    return st


NATURE = {
    "tree_round_a": lambda: tree_round(0), "tree_round_b": lambda: tree_round(1), "tree_round_c": lambda: tree_round(2),
    "tree_pine_a": lambda: tree_pine(0), "tree_pine_b": lambda: tree_pine(1),
    "tree_blossom": lambda: tree_blossom(0),
    "bush_a": lambda: bush(0), "bush_b": lambda: bush(1), "bush_flower_a": lambda: bush(2),
    "bush_flower_b": lambda: bush(3),
    "rock_a": lambda: rock(0), "rock_b": lambda: rock(1), "rock_c": lambda: rock(2), "rock_big": lambda: rock(3),
    "grass_a": lambda: grass_tuft(0), "grass_b": lambda: grass_tuft(1),
    "flowers_yellow": lambda: flowers(0), "flowers_pink": lambda: flowers(1), "flowers_white": lambda: flowers(2),
    "flowers_violet": lambda: flowers(3),
    "reeds": lambda: reeds(0),
}
DRESSING = {
    "fence_wood": lambda: fence_wood(0), "fence_steel": lambda: fence_steel(0), "windsock": lambda: windsock(0),
    "hay_bale": lambda: hay_bale(0), "bench_wood": lambda: bench(0), "bench_steel": lambda: bench(1),
    "monument": lambda: monument(0), "planter_wood": lambda: planter(0), "planter_stone": lambda: planter(1),
    "floodlight": lambda: floodlight(0), "beacon_mast": lambda: beacon_mast(0), "picnic_table": lambda: picnic_table(0),
    "crate_stack": lambda: crate_stack(0), "fuel_cart": lambda: fuel_cart(0),
}


def downsample(st, f):
    """f x f x f blocks -> one voxel (the block's most common colour when at least 3 of its 8
    voxels are filled). Trees, bushes and rocks are modelled at 10 cm and meshed at 20 cm:
    a quarter of the triangles, and the chunkier blocks read better from the game camera."""
    nx, ny, nz = (st.nx + f - 1) // f, (st.ny + f - 1) // f, (st.nz + f - 1) // f
    a = np.zeros((nx * f, ny * f, nz * f), np.uint8)
    a[:st.nx, :st.ny, :st.nz] = st.col
    b = a.reshape(nx, f, ny, f, nz, f).transpose(0, 2, 4, 1, 3, 5).reshape(nx, ny, nz, f ** 3)
    filled = (b > 0).sum(-1)
    out = np.zeros((nx, ny, nz), np.uint8)
    for c in np.unique(b[b > 0]):
        cnt = (b == c).sum(-1)
        better = cnt > np.where(out > 0, (b == out[..., None]).sum(-1), 0)
        out[better] = c
    out[filled < max(1, (f ** 3) * 3 // 8)] = 0
    small = Stamp(0.1, 0.1, 0.1)
    small.col = out
    small.nx, small.ny, small.nz = nx, ny, nz
    small.ox, small.oz = st.ox // f, st.oz // f
    return small


COARSE = 2   # downsample factor for trees, bushes and rocks


def export_stamp(st, path, mat, factor=1):
    if factor > 1:
        st = downsample(st, factor)
    g = Grid(-st.nx / 20 - 0.1, st.nx / 20 + 0.1, st.ny / 10 + 0.1, -st.nz / 20 - 0.1, st.nz / 20 + 0.1)
    g.stamp(st, 0.0, 0.0)
    m = cv.mesh_grid(g)
    pos, nrm, col, idx, org = m[cv.BASE]
    pos = pos * factor
    path.parent.mkdir(parents=True, exist_ok=True)
    cv.write_glb(path, [("Model", (pos, nrm, col, idx), org)])
    cv.write_import(path, "res://" + path.relative_to(ROOT).as_posix(), mat)
    return len(idx) // 3


def main():
    total = 0
    for group, table, mat in (("nature", NATURE, FOLIAGE_MAT), ("dressing", DRESSING, MAT)):
        for name, fn in table.items():
            p = ROOT / "assets" / "campus" / group / f"{name}.glb"
            coarse = name.startswith(("tree", "bush", "rock", ))
            tris = export_stamp(fn(), p, mat, COARSE if coarse else 1)
            total += p.stat().st_size
            print(f"{group}/{name}: {tris} tris, {p.stat().st_size // 1024} KB")
    print(f"total {total / 1024:.0f} KB")


if __name__ == "__main__":
    main()
